# dotfiles

Personal dotfiles for PowerShell, AWS CLI, and AI tooling.

## Structure

- [powershell/](powershell/README.md): profile, setup, AWS/Git helpers
- [aws/](aws/README.md): AWS config
- [ai/](ai/README.md): AI config, agents, helpers
- [RELEASES.md](RELEASES.md): release notes

## Quick Start (Windows)

```powershell
cd "$env:USERPROFILE\dotfiles\powershell"
.\setup.ps1
```

`setup.ps1` will:

- Request Administrator privileges (required for symlinks)
- Use the current checkout when run from this repo; otherwise clone/update `%USERPROFILE%\dotfiles` as needed
- Symlink PowerShell profile files to `powershell/profile.ps1`
- Symlink `%USERPROFILE%\.aws\config` to `aws/config`
- Offer to reload your profile
