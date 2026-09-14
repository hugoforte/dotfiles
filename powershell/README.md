# PowerShell

PowerShell profile setup and helper functions.

## Files

- `profile.ps1`: profile entrypoint, `list-functions`, helper loader
- `aws.ps1`: AWS helper functions
- `git.ps1`: Git helper functions
- `rig.ps1`: rig (cross-repo work harness) launcher
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
- `aws-setup-profile` (copies `aws/config` to `%USERPROFILE%\\.aws\\config`)
- `aws-view-profile` (prints `%USERPROFILE%\\.aws\\config`)
- `aws-goto-profile-path` (changes directory to `%USERPROFILE%\\.aws`)
- `git-list-merged-branches`
- `git-delete-merged-branches`
- `rig` (cross-repo work harness — see [hugoforte/rig](https://github.com/hugoforte/rig))
- `rig-goto-root`

## Notes

- `profile.ps1` resolves symlink targets when loading `aws.ps1` and `git.ps1`
- Fallback loader path: `%USERPROFILE%\dotfiles\powershell`
- `rig` looks for a checkout at `RIG_ROOT`, `D:\\rig`, `C:\\rig`, then `%USERPROFILE%\\rig`; it prints install steps when none is found
