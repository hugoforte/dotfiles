# PowerShell

PowerShell profile, helper functions, and the setup script that symlinks them into place.

Once `setup.ps1` has run, every PowerShell host loads `profile.ps1`, which in turn loads the helper files below. Run `list-functions` in a new shell to confirm.

## Files

- `profile.ps1`: profile entrypoint, `list-functions`, helper loader
- `aws.ps1`: AWS helper functions
- `git.ps1`: Git helper functions
- `rig.ps1`: rig (cross-repo work harness) launcher
- `setup.ps1`: symlink/setup automation
- `sync.ps1`: `git pull --ff-only`, then `ai/install.sh`, then `deploy-secrets.ps1` if the machine has opted in; logs to `%LOCALAPPDATA%\dotfiles\sync.log`
- `deploy-secrets.ps1`: decrypts `ai/secrets/` and symlinks the files into every checkout that has the skill (`-Check` for report only); see `ai/secrets/README.md`
- `install-sync-task.ps1`: registers the "Dotfiles Sync" scheduled task that runs `sync.ps1` at logon and every 4 hours (`-Uninstall` removes it)

## Setup

```powershell
cd <path-to-dotfiles>\powershell
.\setup.ps1
```

What it does, idempotently:

- Re-launches itself elevated (symlinks need admin unless Developer Mode is on)
- Uses the checkout it is run from; if run from elsewhere, clones or updates `%USERPROFILE%\dotfiles`
- Symlinks `$PROFILE` and the all-hosts profile to `profile.ps1`, backing up any regular file it replaces
- Symlinks `%USERPROFILE%\.aws\config` to `aws/config`
- Offers to reload the profile

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
- `rig-install [-Path <dir>] [-Email <address>] [-DataRepo <owner/name>]` (clones the tool, optionally its private data repo as `rig-data` beside it, and runs `rig init`; records a non-default path in `RIG_ROOT`)
- `rig-goto-root`
- `dotfiles-sync` (runs `sync.ps1` in the foreground)

## Notes

- `profile.ps1` resolves symlink targets when loading `aws.ps1` and `git.ps1`
- Fallback loader path: `%USERPROFILE%\dotfiles\powershell`
- `rig` looks for a checkout at `RIG_ROOT`, `D:\\rig`, `C:\\rig`, then `%USERPROFILE%\\rig`; it prints install steps when none is found
