# PowerShell Dotfiles Setup Script
# This script sets up your PowerShell profile from the dotfiles repository

param(
    [string]$RepoUrl = "https://github.com/hugoforte/dotfiles.git",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== PowerShell Dotfiles Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin (required for symlinks)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    
    # Relaunch script as Administrator
    $scriptPath = $PSCommandPath
    $args = @()
    if ($RepoUrl -ne "https://github.com/hugoforte/dotfiles.git") {
        $args += "-RepoUrl", $RepoUrl
    }
    if ($Force) {
        $args += "-Force"
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -Command & { cd '$($PWD.Path)'; & '$scriptPath' $($args -join ' ') }" -Verb RunAs
    exit
}

# Set clone destination
$dotfilesPath = "$env:USERPROFILE\dotfiles"

# Check if dotfiles already exist
if (Test-Path $dotfilesPath) {
    if ($Force) {
        Write-Host "Removing existing dotfiles at $dotfilesPath..." -ForegroundColor Yellow
        Remove-Item $dotfilesPath -Recurse -Force
    } else {
        Write-Host "ERROR: Dotfiles already exist at $dotfilesPath" -ForegroundColor Red
        Write-Host "Use -Force to overwrite" -ForegroundColor Yellow
        exit 1
    }
}

# Clone the repository
Write-Host "Cloning dotfiles repository..." -ForegroundColor Green
Write-Host "Repository: $RepoUrl" -ForegroundColor DarkGray
git clone $RepoUrl $dotfilesPath
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to clone repository" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Repository cloned successfully" -ForegroundColor Green
Write-Host ""

# Create WindowsPowerShell directory if needed
$psDir = "$env:USERPROFILE\Documents\WindowsPowerShell"
if (!(Test-Path $psDir)) {
    Write-Host "Creating PowerShell directory..." -ForegroundColor Green
    mkdir $psDir | Out-Null
    Write-Host "[OK] Created $psDir" -ForegroundColor Green
}

# Backup existing profile if it exists
if (Test-Path $PROFILE) {
    $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Host "Backing up existing profile..." -ForegroundColor Yellow
    Copy-Item $PROFILE $backupPath
    Write-Host "[OK] Backup saved to: $backupPath" -ForegroundColor Green
}

# Create symbolic link
Write-Host "Creating symbolic link..." -ForegroundColor Green
New-Item -ItemType SymbolicLink -Path $PROFILE -Target "$dotfilesPath\powershell\profile.ps1" -Force | Out-Null
Write-Host "[OK] Symbolic link created successfully" -ForegroundColor Green

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Dotfiles location: $dotfilesPath" -ForegroundColor DarkGray
Write-Host "Profile location:  $PROFILE" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To reload your profile, run:" -ForegroundColor Cyan
Write-Host "  & `$PROFILE" -ForegroundColor White
Write-Host ""
Write-Host "To verify AWS functions are loaded, try:" -ForegroundColor Cyan
Write-Host "  aws-whoami" -ForegroundColor White
Write-Host ""

# Ask if user wants to reload now
$reload = Read-Host "Reload profile now? (Y/n)"
if ($reload -ne "n" -and $reload -ne "N") {
    Write-Host "Reloading profile..." -ForegroundColor Green
    & $PROFILE
    Write-Host "[OK] Profile reloaded" -ForegroundColor Green
}
