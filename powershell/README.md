# PowerShell

PowerShell profile, helper functions, and the setup script that symlinks them into place.

Once `setup.ps1` has run, every PowerShell host loads `profile.ps1`, which in turn loads `aws.ps1`, `git.ps1`, `rig.ps1` and `markdown.ps1`. Run `list-functions` in a new shell to confirm. The other files below are run, or dot-sourced, by the scripts that need them — not by the profile.

## Files

- `profile.ps1`: profile entrypoint, `list-functions`, helper loader
- `aws.ps1`: AWS helper functions
- `git.ps1`: Git helper functions
- `rig.ps1`: rig (cross-repo work harness) launcher
- `markdown.ps1`: `md-lint` wrapper around markdownlint-cli2
- `output.ps1`: the reporting vocabulary and the result object the scripts return
- `tools.psd1`: the tools and programs a machine needs, declared
- `install-tools.ps1`: installs what `tools.psd1` declares (`-Check` reports only)
- `markdownlint.jsonc`: default markdownlint rules, used by `md-lint` when a repo has none of its own
- `setup.ps1`: symlink/setup automation
- `sync.ps1`: `git pull --ff-only`, then `ai/install.sh`, then `install-tools.ps1` if `tools.psd1` changed, then `deploy-secrets.ps1` if the machine has opted in; logs to `%LOCALAPPDATA%\dotfiles\sync.log`
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
- Installs every tool declared in `tools.psd1`, including those the scheduled task is not allowed to install unwatched
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
- `dotfiles-tools [-Check]` (runs `install-tools.ps1`; `-Check` reports what is missing and installs nothing)
- `md-lint [args]` (markdownlint-cli2 with the dotfiles default rules, unless the current directory ships its own config)

## Reporting

`install-tools.ps1` and `deploy-secrets.ps1` report through `output.ps1`; `sync.ps1` dot-sources it to *read* what they return, and opens no result of its own. `Ok`, `Change`, `Warn`, `Todo` and `Fail` each print a line and record it on a result object; `Say` only prints, because chatter is not an outcome. Run with `-PassThru`, the script returns that result - counts plus messages - and `sync.ps1` writes it to `sync.log`. The console, the log and the exit code are three adapters over one result.

A closing summary counts outcomes already reported, so it goes through `Summary <Kind> <message>`, which prints in that outcome's style without recording one. Recording it would inflate the counts it is summarising, and the caller would read one more warning than there were problems.

The result is what crosses the call boundary: `Write-Host` writes to the information stream, which Windows PowerShell 5.1 does not capture through `| Out-String`, so a caller that pipes a child script gets an empty string.

| Outcome | Prefix | `output.ps1` | `ai/helpers/output.sh` |
|---|---|---|---|
| ok | `[OK]` | `Ok` | `success` |
| changed | `[..]` | `Change` | - |
| warning | `[!!]` | `Warn` | `warning` |
| to do | `[->]` | `Todo` | - |
| error | `[XX]` | `Fail` | `error` |

Both languages use the same prefixes, in ASCII: neither `sync.log` nor the Windows console is reliably UTF-8.

## Notes

- `profile.ps1` resolves symlink targets when loading `aws.ps1` and `git.ps1`
- Fallback loader path: `%USERPROFILE%\dotfiles\powershell`
- `rig` looks for a checkout at `RIG_ROOT`, `D:\\rig`, `C:\\rig`, then `%USERPROFILE%\\rig`; it prints install steps when none is found
