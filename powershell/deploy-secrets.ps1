# Decrypt managed skill secrets from ai/secrets/ and symlink them into every matching checkout.
#
#   deploy-secrets.ps1            decrypt, discover, link; report each target
#   deploy-secrets.ps1 -Check     report only; exit 1 if anything would change
#   deploy-secrets.ps1 -PassThru  also return the result object, for a caller that reads it
#
# Reads ai/secrets/machine.local.psd1 (per machine, ignored) and the ai/secrets/registry.psd1 of this
# repo and of every overlay it lists (see overlays.ps1). Each skill decrypts from the root that registered it.
# Decrypted files live in %USERPROFILE%\.agent-secrets\<skill>\ and are shared by all checkouts via symlinks.
# An entry with no Marker belongs to a shipped skill, which reads its files from there and is never linked.
# Idempotent. Never overwrites a real file without backing it up. A failed decrypt leaves the previous
# decrypted copy in place.

param(
    [switch]$Check,
    [switch]$Quiet,
    [switch]$PassThru
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "output.ps1")
. (Join-Path $PSScriptRoot "managed-link.ps1")
. (Join-Path $PSScriptRoot "native.ps1")
. (Join-Path $PSScriptRoot "overlays.ps1")

$repoRoot = Split-Path $PSScriptRoot -Parent
$secretsDir = Join-Path $repoRoot "ai\secrets"
$localPath = Join-Path $secretsDir "machine.local.psd1"
$secretsHome = Join-Path $env:USERPROFILE ".agent-secrets"

# What -Check found out of place. Counted at the sites that mean "this would change", which is
# not every warning: a failed decrypt or an origin mismatch is a problem to look at, not an
# item deploy-secrets.ps1 would fix on the next run.
$drift = 0

$result = New-ScriptResult -Name "deploy-secrets.ps1" -Quiet:$Quiet -PassThru:$PassThru

# --- Preconditions --------------------------------------------------------------------------------

if (-not (Get-Command sops -ErrorAction SilentlyContinue)) {
    Fail "sops not found. Install with: winget install SecretsOPerationS.SOPS"
    Exit-WithResult $result 1
}
if (-not (Test-Path $localPath)) {
    Fail "$localPath not found. Copy machine.local.psd1.example to machine.local.psd1 and set SearchRoots."
    Exit-WithResult $result 1
}

try {
    $overlays = Get-OverlayList -LocalPath $localPath
    $skills = @(Get-MergedSkillRegistry -Roots (@($repoRoot) + $overlays))
} catch {
    Fail $_.Exception.Message
    Exit-WithResult $result 1
}
$local = Import-PowerShellDataFile $localPath
$roots = @($local.SearchRoots | Where-Object { Test-Path $_ })
if ($roots.Count -eq 0) {
    Fail "none of the SearchRoots in machine.local.psd1 exist"
    Exit-WithResult $result 1
}

# --- Phase 1: decrypt to %USERPROFILE%\.agent-secrets\<skill>\ -------------------------------------

Say "Decrypting to $secretsHome" Cyan
foreach ($skill in $skills) {
    $outDir = Join-Path $secretsHome $skill.Id
    foreach ($file in $skill.Files) {
        $encrypted = Join-Path $skill.SecretsDir $file
        $decrypted = Join-Path $outDir $file
        if (-not (Test-Path $encrypted)) { Warn "$($skill.Id)/$file missing from $($skill.SecretsDir)"; continue }

        $tmp = "$decrypted.tmp"
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
        $decrypt = Invoke-Native sops decrypt --output $tmp $encrypted
        if (-not $decrypt.Ok -or -not (Test-Path $tmp)) {
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
            $drift++
            Warn "$($skill.Id)/$file would be updated"
        } else {
            Move-Item $tmp $decrypted -Force
            Change "$($skill.Id)/$file decrypted"
        }
    }
}

# --- Phase 2 + 3: discover checkouts and link -----------------------------------------------------

function Get-OriginUrl { param([string]$Dir)
    try { $u = git -C $Dir remote get-url origin 2>$null; if ($LASTEXITCODE -eq 0) { return $u } } catch {}
    return $null
}

Say "" ; Say "Checkouts under: $($roots -join ', ')" Cyan
foreach ($root in $roots) {
    foreach ($dir in Get-ChildItem -Path $root -Directory) {
        foreach ($skill in $skills) {
            if (-not $skill.Marker) { continue }
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

                if ($Check) {
                    $state = Test-ManagedLink -Path $target -Source $source
                    if ($state.IsCorrect) { Ok $label; continue }
                    $drift++
                    if ($state.Reason -eq "Missing") { Warn "$label`: missing" } else { Warn "$label`: exists and is not the managed link" }
                    continue
                }

                # Back up outside the checkout so plaintext never risks being committed there.
                $backupDir = Join-Path $secretsHome "backups\$($dir.Name)\$($skill.Id)"
                $link = Set-ManagedLink -Path $target -Source $source -BackupDir $backupDir
                if ($link.Action -eq "AlreadyCorrect") { Ok $label; continue }
                if ($link.BackupPath) { Change "$label`: moved existing file to $($link.BackupPath)" }
                Change "$label`: linked"
            }
        }
    }
}

# Anything warned about is a reason to exit 1. The summary reports through Summary, which does
# not record, so these counts mean the same before and after it.
Say ""
if ($result.Warned -eq 0) {
    Summary Ok $(if ($Check) { "Everything in place." } else { "Done." })
} else {
    if ($drift -gt 0) { Summary Warn "$drift item(s) would change. Run deploy-secrets.ps1 to apply." }
    $problems = $result.Warned - $drift
    if ($problems -gt 0) { Summary Warn "$problems warning(s) that deploying will not fix; see above." }
}

Exit-WithResult $result $(if ($result.Warned -gt 0) { 1 } else { 0 })
