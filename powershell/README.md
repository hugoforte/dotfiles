# PowerShell

PowerShell profile setup and helper functions.

## Files

- `profile.ps1`: profile entrypoint, `list-functions`, helper loader
- `aws.ps1`: AWS helper functions
- `git.ps1`: Git helper functions
- `setup.ps1`: symlink/setup automation

## Setup

```powershell
cd "$env:USERPROFILE\dotfiles\powershell"
.\setup.ps1
```

## Functions

- `list-functions`
- `aws-whoami`
- `aws-profile [ProfileName]`
- `aws-switch-profile`
- `aws-switch-profiles`
- `git-list-merged-branches`
- `git-delete-merged-branches`

## Notes

- `profile.ps1` resolves symlink targets when loading `aws.ps1` and `git.ps1`
- Fallback loader path: `%USERPROFILE%\dotfiles\powershell`
