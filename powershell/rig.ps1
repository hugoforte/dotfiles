$script:RigRootCandidates = @(
    $env:RIG_ROOT,
    "D:\rig",
    "C:\rig",
    (Join-Path $env:USERPROFILE "rig")
)

function Get-RigRoot {
    foreach ($candidate in $script:RigRootCandidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        # [System.IO.Path]::Combine rather than Join-Path: Join-Path throws on a
        # candidate whose drive does not exist, which is exactly the case we are
        # probing for.
        $entry = [System.IO.Path]::Combine($candidate, "bin\rig.mjs")

        if (Test-Path -LiteralPath $entry -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function rig {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $root = Get-RigRoot

    if (-not $root) {
        Write-Host "rig is not installed on this machine." -ForegroundColor Red
        Write-Host ""
        Write-Host "Looked in:" -ForegroundColor Cyan
        foreach ($candidate in $script:RigRootCandidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            Write-Host "  $candidate" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Install it with:" -ForegroundColor Cyan
        Write-Host "  rig-install                    # D:\rig, or %USERPROFILE%\rig without a D: drive" -ForegroundColor White
        Write-Host "  rig-install -Path <dir>        # anywhere else" -ForegroundColor White
        Write-Host ""
        Write-Host "Or set RIG_ROOT to an existing checkout." -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "rig needs Node.js 18+ on PATH, and node was not found." -ForegroundColor Red
        return
    }

    node ([System.IO.Path]::Combine($root, "bin\rig.mjs")) @Arguments
}

function rig-install {
    param(
        [string]$Path,
        [string]$Email,
        [string]$DataRepo,
        [Alias("h", "?")]
        [switch]$Help
    )

    if ($Help) {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  rig-install [-Path <dir>] [-Email <address>] [-DataRepo <owner/name>]" -ForegroundColor White
        Write-Host ""
        Write-Host "Clones hugoforte/rig and runs 'rig init'. Default path is D:\rig, or" -ForegroundColor White
        Write-Host "%USERPROFILE%\rig without a D: drive. A non-default path is recorded in the" -ForegroundColor White
        Write-Host "RIG_ROOT user environment variable so 'rig' finds it in new shells." -ForegroundColor White
        Write-Host "-Email fills the commit identity for every org in rig.local.json." -ForegroundColor White
        Write-Host "-DataRepo also clones a private data repo (catalogue, work records," -ForegroundColor White
        Write-Host "rig.json) next to the tool, as '<parent>\rig-data', and points dataRoot at it." -ForegroundColor White
        Write-Host ""
        Write-Host "Needs: git, Node.js 18+, and an authenticated gh." -ForegroundColor DarkGray
        return
    }

    $existing = Get-RigRoot
    if ($existing) {
        Write-Host "rig is already installed at $existing" -ForegroundColor Yellow
        Write-Host "Run 'node $existing\bin\rig.mjs init' to (re)initialise it." -ForegroundColor DarkGray
        return
    }

    foreach ($tool in @("git", "node", "gh")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            Write-Host "rig-install needs '$tool' on PATH, and it was not found." -ForegroundColor Red
            return
        }
    }

    if (-not $Path) {
        $Path = if (Test-Path "D:\") { "D:\rig" } else { Join-Path $env:USERPROFILE "rig" }
    }
    $Path = [System.IO.Path]::GetFullPath($Path)

    if (Test-Path -LiteralPath $Path) {
        Write-Host "$Path already exists but has no bin\rig.mjs. Remove it or pick another -Path." -ForegroundColor Red
        return
    }

    Write-Host "Cloning hugoforte/rig to $Path…" -ForegroundColor Cyan
    gh repo clone hugoforte/rig $Path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Clone failed. Is gh authenticated (gh auth status) and do you have access to hugoforte/rig?" -ForegroundColor Red
        return
    }

    if ($script:RigRootCandidates -notcontains $Path) {
        [Environment]::SetEnvironmentVariable("RIG_ROOT", $Path, "User")
        $env:RIG_ROOT = $Path
        $script:RigRootCandidates = @($Path) + $script:RigRootCandidates
        Write-Host "Set RIG_ROOT=$Path (user environment) so 'rig' finds this checkout." -ForegroundColor DarkGray
    }

    $initArgs = @("init")
    if ($Email) { $initArgs += @("--email", $Email) }

    if ($DataRepo) {
        $dataPath = Join-Path (Split-Path $Path -Parent) "rig-data"
        if (Test-Path -LiteralPath $dataPath) {
            Write-Host "$dataPath already exists; using it as the data root without cloning." -ForegroundColor Yellow
        } else {
            Write-Host "Cloning $DataRepo to $dataPath…" -ForegroundColor Cyan
            gh repo clone $DataRepo $dataPath
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Data repo clone failed; continuing with the tool checkout as the data root." -ForegroundColor Red
                $dataPath = $null
            }
        }
        if ($dataPath) { $initArgs += @("--data-root", $dataPath) }
    }

    node ([System.IO.Path]::Combine($Path, "bin\rig.mjs")) @initArgs
}

function rig-goto-root {
    $root = Get-RigRoot

    if (-not $root) {
        Write-Host "rig is not installed on this machine. Run 'rig' for install instructions." -ForegroundColor Red
        return
    }

    Set-Location -LiteralPath $root
}
