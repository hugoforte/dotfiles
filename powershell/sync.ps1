# Pull the dotfiles repo and re-apply the AI tooling links.
# Safe to run unattended: fast-forward only, never commits or pushes.
# Used by the "Dotfiles Sync" scheduled task (see install-sync-task.ps1) and the dotfiles-sync function.

param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $env:LOCALAPPDATA "dotfiles"
$logFile = Join-Path $logDir "sync.log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Path $logFile -Value $line
    if (-not $Quiet) { Write-Host $line }
}

function Find-Sh {
    # Git Bash's sh.exe lives next to git: <Git>\cmd\git.exe -> <Git>\bin\sh.exe
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $gitRoot = Split-Path (Split-Path $git -Parent) -Parent
        foreach ($candidate in @("$gitRoot\bin\sh.exe", "$gitRoot\usr\bin\sh.exe")) {
            if (Test-Path $candidate) { return $candidate }
        }
    }
    foreach ($candidate in @("$env:ProgramFiles\Git\bin\sh.exe", "$env:LOCALAPPDATA\Programs\Git\bin\sh.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

Write-Log "sync start ($repoRoot)"

Push-Location $repoRoot
try {
    $status = git status --porcelain
    if ($status) {
        Write-Log "working tree dirty; pulling anyway (ff-only) but local changes are yours to commit"
    }

    $before = git rev-parse HEAD
    $pullOutput = git pull --ff-only 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Log "git pull failed: $($pullOutput.Trim())"
        exit 1
    }
    $after = git rev-parse HEAD
    if ($before -eq $after) {
        Write-Log "already up to date at $($after.Substring(0,7))"
    } else {
        Write-Log "updated $($before.Substring(0,7)) -> $($after.Substring(0,7))"
    }

    $sh = Find-Sh
    if (-not $sh) {
        Write-Log "sh.exe (Git Bash) not found; skipping ai/install.sh"
        exit 1
    }

    $installOutput = & $sh "$repoRoot/ai/install.sh" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ai/install.sh failed:`n$installOutput"
        exit 1
    }
    Write-Log "ai/install.sh ok"
}
finally {
    Pop-Location
}

Write-Log "sync done"
