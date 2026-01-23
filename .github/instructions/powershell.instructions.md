---
applyTo: "powershell/**/*.ps1"
---

# PowerShell Development Patterns

This file contains implementation patterns specific to PowerShell scripts in this dotfiles repository.

## Function Definition Pattern

**Pattern:** Functions use lowercase kebab-case naming with descriptive verb-noun structure.

```powershell
function aws-whoami {
    Write-Host "Current AWS Identity:" -ForegroundColor Cyan
    aws sts get-caller-identity
}

function aws-profile {
    param([string]$ProfileName)

    if ($ProfileName) {
        $env:AWS_PROFILE = $ProfileName
        Write-Host "Switched to AWS profile: $ProfileName" -ForegroundColor Green
        aws sts get-caller-identity
    } else {
        if ($env:AWS_PROFILE) {
            Write-Host "Current profile: $env:AWS_PROFILE" -ForegroundColor Cyan
        } else {
            Write-Host "Using default profile" -ForegroundColor Cyan
        }
    }
}
```

**Key points:**
- Functions without parameters: simple verb-noun naming (`aws-whoami`, `list-functions`)
- Functions with parameters: use `param()` block for type-safe parameters
- Always provide user feedback with color-coded `Write-Host` messages

## Interactive Menu Pattern

**Pattern:** Use numbered menus with cancel option and clear visual feedback.

```powershell
function aws-switch-profile {
    # ... build profiles array ...

    Write-Host "`nAvailable AWS Profiles:" -ForegroundColor Cyan
    Write-Host "------------------------" -ForegroundColor Cyan

    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $marker = if ($profiles[$i] -eq $env:AWS_PROFILE) { " (current)" } else { "" }
        Write-Host "  [$($i + 1)] $($profiles[$i])$marker" -ForegroundColor White
    }

    Write-Host "`n  [0] Cancel" -ForegroundColor DarkGray
    Write-Host ""

    $selection = Read-Host "Select profile number"

    if ($selection -eq "0" -or $selection -eq "") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    $index = [int]$selection - 1
    if ($index -ge 0 -and $index -lt $profiles.Count) {
        $selectedProfile = $profiles[$index]
        # ... perform action ...
    } else {
        Write-Host "Invalid selection." -ForegroundColor Red
    }
}
```

**Key points:**
- 1-based numbering for user display (more intuitive than 0-based)
- Always include `[0] Cancel` option in `DarkGray`
- Highlight current selection with `(current)` marker
- Validate user input before processing

## Error Recovery with SSO Login

**Pattern:** Detect AWS CLI errors and automatically attempt SSO login recovery.

```powershell
# Try to get caller identity, and if it fails, attempt SSO login
$identity = aws sts get-caller-identity 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Session expired or not logged in. Logging in via SSO..." -ForegroundColor Yellow
    aws sso login
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSuccessfully logged in. Identity:" -ForegroundColor Green
        aws sts get-caller-identity
    } else {
        Write-Host "Failed to log in via SSO." -ForegroundColor Red
    }
} else {
    Write-Output $identity
}
```

**Key points:**
- Capture stderr with `2>&1` to detect errors
- Check `$LASTEXITCODE` after each AWS CLI call
- Attempt automatic recovery (`aws sso login`) before failing
- Provide clear user feedback at each step

## File Parsing with Regex

**Pattern:** Use `Select-String` with regex groups to extract structured data from config files.

```powershell
$configPath = "$env:USERPROFILE\.aws\config"
$profiles = @()

if (Test-Path $configPath) {
    $profiles += Get-Content $configPath |
        Select-String -Pattern '^\[(profile\s+)?(.+)\]$' |
        ForEach-Object { $_.Matches.Groups[2].Value }
}

$profiles = $profiles | Select-Object -Unique | Sort-Object
```

**Key points:**
- Use `Test-Path` before reading files
- `Select-String -Pattern` with capture groups `(.+)`
- Access groups with `$_.Matches.Groups[N].Value`
- Always deduplicate and sort results

## Administrator Privilege Detection

**Pattern:** Detect admin privileges and relaunch with elevation if needed.

```powershell
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
```

**Key points:**
- Use `[Security.Principal.WindowsPrincipal]` to check role
- Relaunch with `Start-Process -Verb RunAs`
- Preserve script path with `$PSCommandPath`
- Preserve parameters with `$PSBoundParameters`
- Preserve working directory with `cd '$($PWD.Path)'`

## Symlink Creation with Idempotency

**Pattern:** Check existing symlinks before creating, backup regular files.

```powershell
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
```

**Key points:**
- Always check if symlink exists and points to correct target
- Use `Get-Item` to inspect `LinkType` property
- Create timestamped backups: `$(Get-Date -Format 'yyyyMMdd_HHmmss')`
- Remove old file before creating symlink
- Use `| Out-Null` to suppress `New-Item` output

## Git Operations with Error Handling

**Pattern:** Validate git operations and provide clear error messages.

```powershell
$ErrorActionPreference = "Stop"

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
```

**Key points:**
- Set `$ErrorActionPreference = "Stop"` at top of script
- Check for `.git` directory to validate repository
- Check `$LASTEXITCODE` after git commands
- Provide detailed error messages with context

## Script Parameters with Defaults

**Pattern:** Use typed parameters with sensible defaults.

```powershell
param(
    [string]$RepoUrl = "https://github.com/haacked/dotfiles.git",
    [switch]$Force
)
```

**Key points:**
- Use `[string]` type annotation for string parameters
- Use `[switch]` for boolean flags
- Provide sensible defaults for optional parameters
- Use `$Force` switch to bypass confirmations

## User Confirmation Pattern

**Pattern:** Ask for confirmation before destructive operations (unless `-Force` is used).

```powershell
if (Test-Path $dotfilesPath) {
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
```

**Key points:**
- Use `Read-Host` for user prompts
- Accept both `n` and `N` for negative responses
- Default to "yes" if user presses Enter (empty string)
- Check `$Force` parameter to bypass confirmations

## Color-Coded Output Standards

**Pattern:** Use consistent colors for different message types.

```powershell
Write-Host "[OK] Operation successful" -ForegroundColor Green
Write-Host "WARNING: File exists" -ForegroundColor Yellow
Write-Host "ERROR: Operation failed" -ForegroundColor Red
Write-Host "=== Section Header ===" -ForegroundColor Cyan
Write-Host "  Optional info" -ForegroundColor DarkGray
Write-Host "  Important command" -ForegroundColor White
```

**Color usage:**
- **Green:** Success messages (prefix with `[OK]`)
- **Yellow:** Warnings or user prompts
- **Red:** Errors (prefix with `ERROR:`)
- **Cyan:** Section headers and informational messages
- **DarkGray:** Optional or cancellation messages
- **White:** Important user-facing content

## Script Completion Summary

**Pattern:** Provide comprehensive completion summary with next steps.

```powershell
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
Write-Host ""

# Ask if user wants to reload now
$reload = Read-Host "Reload profile now? (Y/n)"
if ($reload -ne "n" -and $reload -ne "N") {
    Write-Host "Reloading profile..." -ForegroundColor Green
    & $PROFILE
    Write-Host "[OK] Profile reloaded" -ForegroundColor Green
}
```

**Key points:**
- Show summary with `===` borders in Cyan
- Display important paths in DarkGray
- Provide example commands for next steps
- Offer to perform common next action (reload profile)
