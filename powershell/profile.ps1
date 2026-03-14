# PowerShell Helper Functions

function list-functions {
    Write-Host ""
    Write-Host "=== Available Functions ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "aws-whoami" -ForegroundColor Green
    Write-Host "  Show current AWS identity"
    Write-Host ""

    Write-Host "aws-profile [ProfileName]" -ForegroundColor Green
    Write-Host "  Show or switch AWS profile"
    Write-Host ""

    Write-Host "aws-switch-profile" -ForegroundColor Green
    Write-Host "  Interactive AWS profile switcher"
    Write-Host ""

    Write-Host "list-functions" -ForegroundColor Green
    Write-Host "  Show this function list"
    Write-Host ""

    Write-Host "git-list-merged-branches [options]" -ForegroundColor Green
    Write-Host "  List merged branches (local/remote)"
    Write-Host ""

    Write-Host "git-delete-merged-branches [options]" -ForegroundColor Green
    Write-Host "  Delete merged branches after confirmation"
    Write-Host ""
}

$profilePath = $MyInvocation.MyCommand.Path
$profileItem = Get-Item -LiteralPath $profilePath -ErrorAction SilentlyContinue

if ($profileItem -and $profileItem.LinkType -eq "SymbolicLink" -and $profileItem.Target) {
    $targetPath = $profileItem.Target
    if ($targetPath -is [System.Array]) {
        $targetPath = $targetPath[0]
    }

    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = Join-Path (Split-Path -Parent $profilePath) $targetPath
    }

    $profilePath = $targetPath
}

$profileScriptRoot = Split-Path -Parent $profilePath
$awsHelpersPath = Join-Path $profileScriptRoot "aws.ps1"
$gitHelpersPath = Join-Path $profileScriptRoot "git.ps1"

if (-not (Test-Path $awsHelpersPath) -or -not (Test-Path $gitHelpersPath)) {
    $fallbackRoot = Join-Path $env:USERPROFILE "dotfiles\powershell"
    $fallbackAwsPath = Join-Path $fallbackRoot "aws.ps1"
    $fallbackGitPath = Join-Path $fallbackRoot "git.ps1"

    if ((Test-Path $fallbackAwsPath) -and (Test-Path $fallbackGitPath)) {
        $awsHelpersPath = $fallbackAwsPath
        $gitHelpersPath = $fallbackGitPath
    }
}

if (Test-Path $awsHelpersPath) {
    . $awsHelpersPath
} else {
    Write-Host "WARNING: Could not find aws.ps1 at $awsHelpersPath" -ForegroundColor Yellow
}

if (Test-Path $gitHelpersPath) {
    . $gitHelpersPath
} else {
    Write-Host "WARNING: Could not find git.ps1 at $gitHelpersPath" -ForegroundColor Yellow
}
