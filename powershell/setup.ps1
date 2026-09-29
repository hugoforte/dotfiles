# PowerShell Dotfiles Setup Script
# This script sets up your PowerShell profile from the dotfiles repository
# Idempotent - safe to run multiple times

param(
    [string]$RepoUrl = "https://github.com/hugoforte/dotfiles.git",
    [switch]$Force,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "managed-link.ps1")
. (Join-Path $PSScriptRoot "overlays.ps1")

# The overlays this machine lists; see overlays.ps1.
function Get-SetupOverlays {
    param([Parameter(Mandatory)][string]$RepoPath)
    return @(Get-OverlayList -LocalPath "$RepoPath\ai\secrets\machine.local.psd1")
}

# Every managed link this script owns, in one list, so -Check and the apply path can never
# disagree about what "set up" means.
function Get-ManagedLinkPlan {
    param([Parameter(Mandatory)][string]$RepoPath)

    # AWS config may come from this repo or from one overlay, never both.
    $awsConfig = Find-OverlayFile -Roots (@($RepoPath) + (Get-SetupOverlays -RepoPath $RepoPath)) -RelativePath "aws\config"
    if (-not $awsConfig) {
        Write-Host "[--] AWS config: neither this repo nor an overlay has aws/config; skipped" -ForegroundColor DarkGray
    }

    $plan = @(
        @{ Label = "PowerShell profile";           Path = $PROFILE;                                   Source = "$RepoPath\powershell\profile.ps1" }
        @{ Label = "PowerShell all-hosts profile"; Path = $PROFILE.CurrentUserAllHosts;               Source = "$RepoPath\powershell\profile.ps1" }
        @{ Label = "AWS config";                   Path = "$env:USERPROFILE\.aws\config";             Source = $awsConfig }
        @{ Label = "~/.gitconfig";                 Path = "$env:USERPROFILE\.gitconfig";              Source = "$RepoPath\git\gitconfig" }
    )
    # A source the repo does not ship is not a link this machine is missing.
    return @($plan | Where-Object { $_.Source -and (Test-Path -LiteralPath $_.Source) })
}

# --- Check: report the managed links and change nothing ----------------------------------------
#
# Deliberately before the elevation, the update prompt and the clone: reading state needs none of
# them. This is the -Check that ai/install.sh, install-tools.ps1 and deploy-secrets.ps1 all had
# and this script did not.
if ($Check) {
    Write-Host "=== PowerShell Dotfiles Check ===" -ForegroundColor Cyan
    Write-Host ""

    $repoPath = Split-Path $PSScriptRoot -Parent
    $wrong = 0
    foreach ($entry in (Get-ManagedLinkPlan -RepoPath $repoPath)) {
        $state = Test-ManagedLink -Path $entry.Path -Source $entry.Source
        if ($state.IsCorrect) {
            Write-Host "[OK] $($entry.Label)" -ForegroundColor Green
        } else {
            $wrong++
            $detail = switch ($state.Reason) {
                'Missing'     { "missing" }
                'NotALink'    { "exists and is not a symlink" }
                'WrongTarget' { "points at $($state.ActualTarget)" }
            }
            Write-Host "[!!] $($entry.Label): $detail" -ForegroundColor Yellow
            Write-Host "     expected $($entry.Path) -> $($entry.Source)" -ForegroundColor DarkGray
        }
    }

    # ~/.gitconfig-overlays is generated rather than linked; see overlays.ps1.
    if ((Update-GitOverlayInclude -Overlays (Get-SetupOverlays -RepoPath $repoPath) -Check) -eq 'AlreadyCorrect') {
        Write-Host "[OK] ~/.gitconfig-overlays" -ForegroundColor Green
    } else {
        $wrong++
        Write-Host "[!!] ~/.gitconfig-overlays: missing or out of date" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($wrong -gt 0) {
        Write-Host "$wrong link(s) would change. Run setup.ps1 to apply." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Every managed link is in place." -ForegroundColor Green
    exit 0
}

Write-Host "=== PowerShell Dotfiles Setup ===" -ForegroundColor Cyan
Write-Host ""

# Elevation is NOT for the symlinks. The managed-link module uses `cmd /c mklink`, which honours
# Developer Mode and works unelevated - measured; PowerShell 5.1's New-Item -ItemType SymbolicLink
# does not, which is why this script used to need admin.
#
# What the elevation still earns is install-tools.ps1 below: winget installs machine-wide only
# when elevated, and this deliberate, watched run is where that is wanted. sync.ps1 runs the same
# installer unelevated on purpose, and gets --scope user.
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

# --- The managed links -------------------------------------------------------------------------
#
# Four links, one implementation. This used to be the same ~28-line probe/backup/link block
# written out four times - three inline and once as Set-DotfileSymlink, which was the
# generalisation, defined below the copies that should have used it and called only for the
# gitconfigs. All of it now lives in managed-link.ps1 (hugoforte/dotfiles#6).

# Parent directories the links need. Set-ManagedLink creates a missing parent itself, but these
# two are directories Windows and the AWS CLI expect to exist in their own right, not just as
# somewhere to put a link.
foreach ($dir in @("$env:USERPROFILE\Documents\WindowsPowerShell", "$env:USERPROFILE\.aws")) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[OK] Created $dir" -ForegroundColor Green
    }
}

Write-Host "Linking managed files..." -ForegroundColor Green
$linkedAws = $false
foreach ($entry in (Get-ManagedLinkPlan -RepoPath $dotfilesPath)) {
    $result = Set-ManagedLink -Path $entry.Path -Source $entry.Source

    switch ($result.Action) {
        'AlreadyCorrect'    { Write-Host "[OK] $($entry.Label) already linked correctly" -ForegroundColor Green }
        'Created'           { Write-Host "[OK] $($entry.Label) linked" -ForegroundColor Green }
        'Repointed'         { Write-Host "[OK] $($entry.Label) repointed at the repo" -ForegroundColor Green }
        'BackedUpAndLinked' {
            Write-Host "[OK] $($entry.Label) linked" -ForegroundColor Green
            Write-Host "     backed up what was there to $(Split-Path $result.BackupPath -Leaf)" -ForegroundColor Yellow
        }
    }

    if ($entry.Label -eq "AWS config" -and $result.Action -ne 'AlreadyCorrect') { $linkedAws = $true }
}

if ($linkedAws) {
    Write-Host "     Run 'aws sso login' to authenticate" -ForegroundColor DarkGray
}

switch (Update-GitOverlayInclude -Overlays (Get-SetupOverlays -RepoPath $dotfilesPath)) {
    'AlreadyCorrect' { Write-Host "[OK] ~/.gitconfig-overlays already current" -ForegroundColor Green }
    'Written'        { Write-Host "[OK] ~/.gitconfig-overlays written" -ForegroundColor Green }
}
Write-Host ""
# Tools: this script is already elevated, so the whole manifest installs here, including the
# entries sync.ps1 is not allowed to install unwatched.
Write-Host "Installing declared tools..." -ForegroundColor Green
& (Join-Path $PSScriptRoot "install-tools.ps1")
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
