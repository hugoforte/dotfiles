# PowerShell Dotfiles

My personal PowerShell profile with AWS helper functions and utilities for managing AWS credentials across machines.

## Contents

- `profile.ps1` - PowerShell profile with AWS helper functions
- `setup.ps1` - Automated setup script for new machines
- `README.md` - This file

### AWS Functions

- **`list-functions`** - Display help for all available functions
- **`aws-whoami`** - Display current AWS identity
- **`aws-profile [ProfileName]`** - Switch to or display the current AWS profile
- **`aws-switch-profile`** - Interactive menu to browse and switch AWS profiles with SSO login support

## Setup Instructions

### Option 1: Automated Setup (Recommended)

Download and run the setup script in PowerShell:

```powershell
# Download and run setup script
irm https://raw.githubusercontent.com/yourusername/dotfiles/main/setup.ps1 | iex
```

Or if you've already cloned the repo:

```powershell
cd "$env:USERPROFILE\dotfiles"
.\setup.ps1
```

The script will automatically request Administrator privileges if needed.

**Setup script features:**
- Automatically requests elevated privileges
- Clones the repo
- Creates necessary directories
- Backs up your existing profile
- Creates a symbolic link to the profile

**Options:**
```powershell
.\setup.ps1 -RepoUrl "https://github.com/yourusername/dotfiles.git"  # Specify repo URL
.\setup.ps1 -Force                                                   # Overwrite if already exists
```

### Option 2: Manual Setup

1. Clone the repository:
   ```powershell
   git clone https://github.com/yourusername/dotfiles.git "$env:USERPROFILE\dotfiles"
   ```

2. Open your PowerShell profile:
   ```powershell
   notepad $PROFILE
   ```

3. Add this line to the end of your profile:
   ```powershell
   . "$env:USERPROFILE\dotfiles\profile.ps1"
   ```

4. Save and reload:
   ```powershell
   & $PROFILE
   ```

## Syncing Across Machines

Since the profile is linked (or sourced) from the cloned repository, simply pull the latest changes:

```powershell
cd "$env:USERPROFILE\dotfiles"
git pull
& $PROFILE  # Reload if you made changes
```

To keep everything in sync, pull regularly or set up a scheduled task.

## Adding New Functions

1. Edit `profile.ps1` in your dotfiles repo
2. Commit and push changes
3. Pull on other machines to sync

```powershell
cd "$env:USERPROFILE\dotfiles"
git add .
git commit -m "Add new function: function-name"
git push origin main
```

## Prerequisites

- PowerShell 5.1 or higher
- Git installed and configured
- AWS CLI (for AWS helper functions)

## Updating

To update your profile on any machine:

```powershell
cd "$env:USERPROFILE\dotfiles"
git pull origin main
```

Your profile will automatically use the updated version on your next PowerShell restart (or reload with `& $PROFILE`).

## License

Personal use - feel free to fork and modify for your own setup.
