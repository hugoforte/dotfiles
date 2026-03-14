# PowerShell Dotfiles Setup Script
# This script sets up your PowerShell profile from the dotfiles repository
# Idempotent - safe to run multiple times

param(
    [string]$RepoUrl = "https://github.com/haacked/dotfiles.git",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "=== PowerShell Dotfiles Setup ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin (required for symlinks on Windows)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Requesting Administrator privileges..." -ForegroundColor Yellow
    
    # Relaunch script as Administrator
    $scriptPath = $PSCommandPath
    $args = $PSBoundParameters.GetEnumerator() | ForEach-Object { "-$($_.Key)", "$($_.Value)" }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoExit -Command & { cd '$($PWD.Path)'; & '$scriptPath' $($args -join ' ') }" -Verb RunAs
    exit
}

# Detect dotfiles path - either use existing location or default
$dotfilesPath = "$env:USERPROFILE\dotfiles"

# Check if we're already running from within dotfiles repo
if ($PSScriptRoot -match "dotfiles") {
    # We're running from within the dotfiles repo, go up one level from powershell folder
    $potentialPath = Split-Path $PSScriptRoot -Parent
    if (Test-Path "$potentialPath\.git") {
        $dotfilesPath = $potentialPath
        Write-Host "Detected existing dotfiles at: $dotfilesPath" -ForegroundColor Green
    }
} elseif (Test-Path $dotfilesPath) {
    if (Test-Path "$dotfilesPath\.git") {
        Write-Host "Found existing dotfiles at: $dotfilesPath" -ForegroundColor Green
        $update = Read-Host "Update repository? (Y/n)"
        if ($update -ne "n" -and $update -ne "N") {
            Write-Host "Pulling latest changes..." -ForegroundColor Green
            Push-Location $dotfilesPath
            git pull
            Pop-Location
            Write-Host "[OK] Repository updated" -ForegroundColor Green
        }
    } elseif ($Force) {
        Write-Host "Removing existing directory at $dotfilesPath..." -ForegroundColor Yellow
        Remove-Item $dotfilesPath -Recurse -Force
    } else {
        Write-Host "ERROR: Directory exists at $dotfilesPath but is not a git repository" -ForegroundColor Red
        Write-Host "Use -Force to overwrite" -ForegroundColor Yellow
        exit 1
    }
}

# Clone the repository if it doesn't exist
if (!(Test-Path "$dotfilesPath\.git")) {
    Write-Host "Cloning dotfiles repository..." -ForegroundColor Green
    Write-Host "Repository: $RepoUrl" -ForegroundColor DarkGray
    git clone $RepoUrl $dotfilesPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to clone repository" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Repository cloned successfully" -ForegroundColor Green
}
Write-Host ""

# Create WindowsPowerShell directory if needed
$psDir = "$env:USERPROFILE\Documents\WindowsPowerShell"
if (!(Test-Path $psDir)) {
    Write-Host "Creating PowerShell directory..." -ForegroundColor Green
    mkdir $psDir | Out-Null
    Write-Host "[OK] Created $psDir" -ForegroundColor Green
}

# Setup PowerShell profile symlink
$profileTarget = "$dotfilesPath\powershell\profile.ps1"
$needsProfileSetup = $false

if (Test-Path $PROFILE) {
    $item = Get-Item $PROFILE
    if ($item.LinkType -eq "SymbolicLink") {
        $currentTarget = $item.Target
        if ($currentTarget -eq $profileTarget) {
            Write-Host "[OK] PowerShell profile already linked correctly" -ForegroundColor Green
        } else {
            Write-Host "Profile is symlinked to different location: $currentTarget" -ForegroundColor Yellow
            $needsProfileSetup = $true
        }
    } else {
        Write-Host "Profile exists but is not a symlink" -ForegroundColor Yellow
        $needsProfileSetup = $true
    }
} else {
    $needsProfileSetup = $true
}

if ($needsProfileSetup) {
    # Backup existing profile if it's a regular file
    if ((Test-Path $PROFILE) -and (Get-Item $PROFILE).LinkType -ne "SymbolicLink") {
        $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Host "Backing up existing profile..." -ForegroundColor Yellow
        Copy-Item $PROFILE $backupPath
        Write-Host "[OK] Backup saved to: $backupPath" -ForegroundColor Green
        Remove-Item $PROFILE -Force
    }
    
    Write-Host "Creating symbolic link for PowerShell profile..." -ForegroundColor Green
    New-Item -ItemType SymbolicLink -Path $PROFILE -Target $profileTarget -Force | Out-Null
    Write-Host "[OK] PowerShell profile linked successfully" -ForegroundColor Green
}

# Setup all-hosts PowerShell profile symlink so functions load in any host
$allHostsProfile = $PROFILE.CurrentUserAllHosts
$needsAllHostsSetup = $false

if (Test-Path $allHostsProfile) {
    $item = Get-Item $allHostsProfile
    if ($item.LinkType -eq "SymbolicLink") {
        $currentTarget = $item.Target
        if ($currentTarget -eq $profileTarget) {
            Write-Host "[OK] PowerShell all-hosts profile already linked correctly" -ForegroundColor Green
        } else {
            Write-Host "All-hosts profile is symlinked to different location: $currentTarget" -ForegroundColor Yellow
            $needsAllHostsSetup = $true
        }
    } else {
        Write-Host "PowerShell all-hosts profile exists but is not a symlink" -ForegroundColor Yellow
        $needsAllHostsSetup = $true
    }
} else {
    $needsAllHostsSetup = $true
}

if ($needsAllHostsSetup) {
    if ((Test-Path $allHostsProfile) -and (Get-Item $allHostsProfile).LinkType -ne "SymbolicLink") {
        $backupPath = "$allHostsProfile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Host "Backing up existing all-hosts profile..." -ForegroundColor Yellow
        Copy-Item $allHostsProfile $backupPath
        Write-Host "[OK] Backup saved to: $backupPath" -ForegroundColor Green
        Remove-Item $allHostsProfile -Force
    }

    Write-Host "Creating symbolic link for PowerShell all-hosts profile..." -ForegroundColor Green
    New-Item -ItemType SymbolicLink -Path $allHostsProfile -Target $profileTarget -Force | Out-Null
    Write-Host "[OK] PowerShell all-hosts profile linked successfully" -ForegroundColor Green
}
Write-Host ""

# Setup AWS profiles
$awsDir = "$env:USERPROFILE\.aws"
$dotfilesAwsDir = "$dotfilesPath\aws"

if (Test-Path "$dotfilesAwsDir\config") {
    Write-Host "Setting up AWS profiles..." -ForegroundColor Green
    
    # Create .aws directory if needed
    if (!(Test-Path $awsDir)) {
        mkdir $awsDir | Out-Null
        Write-Host "[OK] Created .aws directory" -ForegroundColor Green
    }
    
    $awsConfigTarget = "$dotfilesAwsDir\config"
    $needsAwsSetup = $false
    
    if (Test-Path "$awsDir\config") {
        $item = Get-Item "$awsDir\config"
        if ($item.LinkType -eq "SymbolicLink") {
            $currentTarget = $item.Target
            if ($currentTarget -eq $awsConfigTarget) {
                Write-Host "[OK] AWS config already linked correctly" -ForegroundColor Green
            } else {
                Write-Host "AWS config is symlinked to different location: $currentTarget" -ForegroundColor Yellow
                $needsAwsSetup = $true
            }
        } else {
            Write-Host "AWS config exists but is not a symlink" -ForegroundColor Yellow
            $needsAwsSetup = $true
        }
    } else {
        $needsAwsSetup = $true
    }
    
    if ($needsAwsSetup) {
        # Backup existing AWS config if it's a regular file
        if ((Test-Path "$awsDir\config") -and (Get-Item "$awsDir\config").LinkType -ne "SymbolicLink") {
            $backupPath = "$awsDir\config.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item "$awsDir\config" $backupPath
            Write-Host "[OK] Backed up existing AWS config to: $(Split-Path $backupPath -Leaf)" -ForegroundColor Yellow
            Remove-Item "$awsDir\config" -Force
        }
        
        New-Item -ItemType SymbolicLink -Path "$awsDir\config" -Target $awsConfigTarget -Force | Out-Null
        Write-Host "[OK] AWS config linked successfully" -ForegroundColor Green
        Write-Host "    Run 'aws sso login' to authenticate" -ForegroundColor DarkGray
    }
}

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
Write-Host "  list-functions" -ForegroundColor White
Write-Host "  aws-whoami" -ForegroundColor White
Write-Host "  aws-switch-profile" -ForegroundColor White
Write-Host ""

# Ask if user wants to reload now
$reload = Read-Host "Reload profile now? (Y/n)"
if ($reload -ne "n" -and $reload -ne "N") {
    Write-Host "Reloading profile..." -ForegroundColor Green
    & $PROFILE
    Write-Host "[OK] Profile reloaded" -ForegroundColor Green
}
