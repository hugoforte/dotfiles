# Decrypt managed skill secrets from ai/secrets/ and symlink them into every matching checkout.
#
#   deploy-secrets.ps1          decrypt, discover, link; report each target
#   deploy-secrets.ps1 -Check   report only; exit 1 if anything would change
#
# Reads ai/secrets/registry.psd1 (tracked) and ai/secrets/machine.local.psd1 (per machine, ignored).
# Decrypted files live in %USERPROFILE%\.agent-secrets\<skill>\ and are shared by all checkouts via symlinks.
# Idempotent. Never overwrites a real file without backing it up. A failed decrypt leaves the previous
# decrypted copy in place.

param(
    [switch]$Check,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$secretsDir = Join-Path $repoRoot "ai\secrets"
$registryPath = Join-Path $secretsDir "registry.psd1"
$localPath = Join-Path $secretsDir "machine.local.psd1"
$secretsHome = Join-Path $env:USERPROFILE ".agent-secrets"
$drift = 0

function Say { param([string]$Message, [string]$Color = "Gray") if (-not $Quiet -or $Color -in @("Yellow", "Red")) { Write-Host $Message -ForegroundColor $Color } }
function Ok      { param([string]$Message) Say "[OK] $Message" Green }
function Change  { param([string]$Message) Say "[..] $Message" Cyan }
function Warn    { param([string]$Message) Say "[!!] $Message" Yellow; $script:drift++ }

# --- Preconditions --------------------------------------------------------------------------------

if (-not (Get-Command sops -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: sops not found. Install with: winget install SecretsOPerationS.SOPS" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $localPath)) {
    Write-Host "ERROR: $localPath not found." -ForegroundColor Red
    Write-Host "       Copy machine.local.psd1.example to machine.local.psd1 and set SearchRoots." -ForegroundColor Yellow
    exit 1
}

$registry = Import-PowerShellDataFile $registryPath
$local = Import-PowerShellDataFile $localPath
$roots = @($local.SearchRoots | Where-Object { Test-Path $_ })
if ($roots.Count -eq 0) {
    Write-Host "ERROR: none of the SearchRoots in machine.local.psd1 exist" -ForegroundColor Red
    exit 1
}

# --- Phase 1: decrypt to %USERPROFILE%\.agent-secrets\<skill>\ -------------------------------------

Say "Decrypting to $secretsHome" Cyan
foreach ($skill in $registry.Skills) {
    $outDir = Join-Path $secretsHome $skill.Id
    foreach ($file in $skill.Files) {
        $encrypted = Join-Path (Join-Path $secretsDir $skill.Id) $file
        $decrypted = Join-Path $outDir $file
        if (-not (Test-Path $encrypted)) { Warn "$($skill.Id)/$file missing from ai/secrets"; continue }

        $tmp = "$decrypted.tmp"
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
        & sops decrypt --output $tmp $encrypted 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
            Remove-Item $tmp -ErrorAction SilentlyContinue
            Warn "$($skill.Id)/$file failed to decrypt (is this machine a recipient in .sops.yaml?)"
            continue
        }
        $same = (Test-Path $decrypted) -and ((Get-FileHash $tmp).Hash -eq (Get-FileHash $decrypted).Hash)
        if ($same) {
            Remove-Item $tmp
            Ok "$($skill.Id)/$file current"
        } elseif ($Check) {
            Remove-Item $tmp
            Warn "$($skill.Id)/$file would be updated"
        } else {
            Move-Item $tmp $decrypted -Force
            Change "$($skill.Id)/$file decrypted"
        }
    }
}

# --- Phase 2 + 3: discover checkouts and link -----------------------------------------------------

# Windows PowerShell 5.1's New-Item -ItemType SymbolicLink demands elevation even in Developer Mode;
# cmd's mklink honours Developer Mode, so use it and fall back to a clear error.
function New-FileSymlink { param([string]$Path, [string]$Target)
    $out = cmd /c mklink "`"$Path`"" "`"$Target`"" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) {
        throw "mklink failed for $Path (enable Developer Mode or run elevated): $($out.Trim())"
    }
}

function Get-OriginUrl { param([string]$Dir)
    try { $u = git -C $Dir remote get-url origin 2>$null; if ($LASTEXITCODE -eq 0) { return $u } } catch {}
    return $null
}

Say "" ; Say "Checkouts under: $($roots -join ', ')" Cyan
foreach ($root in $roots) {
    foreach ($dir in Get-ChildItem -Path $root -Directory) {
        foreach ($skill in $registry.Skills) {
            $markerDir = Join-Path $dir.FullName $skill.Marker
            if (-not (Test-Path $markerDir -PathType Container)) { continue }

            $origin = Get-OriginUrl $dir.FullName
            if (-not $origin -or $origin -notmatch [regex]::Escape($skill.Remote)) {
                Warn "$($dir.Name): has $($skill.Id) but origin '$origin' does not match '$($skill.Remote)'; skipped"
                continue
            }

            foreach ($file in $skill.Files) {
                $source = Join-Path (Join-Path $secretsHome $skill.Id) $file
                $target = Join-Path $markerDir $file
                $label = "$($dir.Name)\$($skill.Marker)\$file"
                if (-not (Test-Path $source)) { Warn "$label`: no decrypted source"; continue }

                $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                if ($item -and $item.LinkType -eq "SymbolicLink" -and ($item.Target | Select-Object -First 1) -eq $source) {
                    Ok $label
                    continue
                }
                if ($Check) {
                    if ($item) { Warn "$label`: exists and is not the managed link" } else { Warn "$label`: missing" }
                    continue
                }
                if ($item -and $item.LinkType -eq "SymbolicLink") {
                    $item.Delete()
                } elseif ($item) {
                    # Back up outside the checkout so plaintext never risks being committed there.
                    $backupDir = Join-Path $secretsHome "backups\$($dir.Name)\$($skill.Id)"
                    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
                    $backup = Join-Path $backupDir "$file.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                    Move-Item -LiteralPath $target -Destination $backup
                    Change "$label`: moved existing file to $backup"
                }
                New-FileSymlink -Path $target -Target $source
                Change "$label`: linked"
            }
        }
    }
}

Say ""
if ($Check) {
    if ($drift -gt 0) { Write-Host "$drift item(s) would change. Run deploy-secrets.ps1 to apply." -ForegroundColor Yellow; exit 1 }
    Write-Host "Everything in place." -ForegroundColor Green
} else {
    if ($drift -gt 0) { Write-Host "Done with $drift warning(s)." -ForegroundColor Yellow; exit 1 }
    Write-Host "Done." -ForegroundColor Green
}
