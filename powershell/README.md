# PowerShell

PowerShell profile, helper functions, and the setup script that symlinks them into place.

Once `setup.ps1` has run, every PowerShell host loads `profile.ps1`, which in turn loads `aws.ps1`, `git.ps1` and `rig.ps1`. Run `list-functions` in a new shell to confirm. The other files below are run, or dot-sourced, by the scripts that need them — not by the profile.

## Files

- `profile.ps1`: profile entrypoint, `list-functions`, helper loader
- `aws.ps1`: AWS helper functions
- `git.ps1`: Git helper functions
- `rig.ps1`: rig (cross-repo work harness) launcher
- `output.ps1`: the reporting vocabulary and the result object the scripts return
- `managed-link.ps1`: the one implementation of "point this path at that file in the repo" — `Set-ManagedLink`, `Test-ManagedLink`, `Remove-ManagedLink`
- `authorized-keys.ps1`: keeps `~/.ssh/authorized_keys` a copy of the one overlay's `ssh/authorized_keys` — `Set-AuthorizedKeysCopy`, `Test-AuthorizedKeysCopy`. A copy rather than a link, because sshd checks the ownership and access of the file it reads
- `overlays.ps1`: the overlay table, one row for each path an overlay may ship. `Get-Overlays` reads the overlays `ai/secrets/machine.local.psd1` lists, the machine key and the overlay repos; `Get-OverlaySource` gives a path's one source or every source, `Get-OverlayEntry` the entries under a directory, `Get-MergedSkillRegistry` the merged registries. Also whether the machine opts into skill secrets, the contents of `~/.gitconfig-overlays`, and the writers of `machine.local.psd1`. `ai/helpers/overlays.sh` is its sh twin
- `aws-config.ps1`: `~/.aws/config`, generated from every `aws/config` in the repo and the overlays, merged (`docs/adr/0010-aws-config-is-generated.md`)
- `generated-file.ps1`: a managed path that holds content dotfiles writes, under a header that says so; `aws-config.ps1` and `authorized-keys.ps1` use it
- `native.ps1`: `Invoke-Native`, which runs a native command and judges it by its exit code, because Windows PowerShell 5.1 under `$ErrorActionPreference = "Stop"` turns any line it writes to stderr — git's progress, say — into a terminating error
- `tools.psd1`: the tools and programs a machine needs, declared
- `install-tools.ps1`: installs what `tools.psd1` and each overlay's `powershell/tools.psd1` declare, then runs the `Configure` script of each entry that has one (`-Check` reports only)
- `tool-selection.ps1`: which manifest entries a machine gets (an optional entry only where `machine.local.psd1` or an overlay's `machines/<KEY>.psd1` lists its option under `OptionalTools`), how the manifests merge, and the pure parts of the `github-release`, `download` and `uv` install methods
- `markdownlint.jsonc`: default markdownlint rules, used by `bin/md-lint` when a repo has none of its own
- `user-path.ps1`: `Add-UserPathEntry`, which puts the repo's `bin/` on the user PATH for `setup.ps1` and `sync.ps1`
- `setup.ps1`: symlink/setup automation (`-Check` reports the managed links and changes nothing)
- `sync.ps1`: `git pull --ff-only`, then `ai/install.sh`, then `bin/` on the user PATH, then each overlay repo pulled and `~/.gitconfig-overlays` written, then `install-tools.ps1` if a manifest or the machine's options changed, then the rest of what the overlays supply re-applied (the merged `~/.aws/config`, removal of links left dangling by files that moved out, the `~/.ssh/authorized_keys` copy), then `deploy-secrets.ps1` if the machine has opted in (its `machine.local.psd1` declares `SearchRoots`) (an overlay repo that fails to pull, or a failed `install-tools.ps1`, is logged, the rest still runs, and the run exits 1); logs to `%LOCALAPPDATA%\dotfiles\sync.log`
- `deploy-secrets.ps1`: decrypts `ai/secrets/` and symlinks the files into every checkout that has the skill (`-Check` for report only); see `ai/secrets/README.md`
- `install-overlays.ps1`: puts this machine on an overlay repo (`-Repo owner/name`, optionally `-Only <overlay>`): clones or pulls it beside this checkout, lists its overlays in `ai/secrets/machine.local.psd1` (creating it from the example, with `SearchRoots` set to the folder this checkout is in, when there is none) after checking they do not clash with the repo, then runs `sync.ps1`
- `install-sync-task.ps1`: registers the "Dotfiles Sync" scheduled task that runs `sync.ps1` at logon and every 4 hours (`-Uninstall` removes it)
- `install-cswap-task.ps1`: registers and starts the "Claude Swap Auto" scheduled task that runs `cswap auto` hidden at sign-in, for a machine with the `claude-swap` option (`-Uninstall` removes it); see the top-level README, "Claude accounts"

## Setup

```powershell
cd <path-to-dotfiles>\powershell
.\setup.ps1
.\setup.ps1 -Check   # report the managed links and change nothing
```

What it does, idempotently:

- Uses the checkout it is run from; if run from elsewhere, clones or updates `%USERPROFILE%\dotfiles`
- Links `$PROFILE`, the all-hosts profile and `~/.gitconfig`, backing up any regular file it displaces
- Writes `%USERPROFILE%\.aws\config` from every `aws/config` in this repo and the overlays, when there is one, backing up a file it did not write
- Writes `~/.gitconfig-overlays`, which includes each overlay's `git/gitconfig`
- Writes `~/.ssh/authorized_keys` from the one overlay that has `ssh/authorized_keys`, backing up a file it did not write
- Puts the repo's `bin/` on the user PATH, so `md-lint` runs in every shell, agents' included
- Installs every tool declared in `tools.psd1`, including those the scheduled task is not allowed to install unwatched
- Offers to reload the profile

`-Check` needs no elevation and does nothing else in the list above: it reports each managed link and whether `bin/` is on the user PATH, and exits non-zero if anything would change.

The elevation is **not** for the symlinks. `managed-link.ps1` uses `cmd /c mklink`, which honours Developer Mode and works unelevated — Windows PowerShell 5.1's `New-Item -ItemType SymbolicLink` does not, whatever Developer Mode says, which is why this script used to need admin. What the elevation earns now is `install-tools.ps1`: winget installs machine-wide only when elevated, and a deliberate, watched `setup.ps1` run is where that is wanted. `sync.ps1` runs the same installer unelevated and gets `--scope user`.

## Functions

- `list-functions`
- `aws-whoami`
- `aws-profile [ProfileName]`
- `aws-switch-profile`
- `aws-switch-profiles`
- `aws-setup-profile` (writes `%USERPROFILE%\\.aws\\config` from every `aws/config` in the repo and the overlays, the same file `setup.ps1` writes)
- `aws-view-profile` (prints `%USERPROFILE%\\.aws\\config`)
- `aws-goto-profile-path` (changes directory to `%USERPROFILE%\\.aws`)
- `git-list-merged-branches` (counts a squash merge as merged, which `git branch --merged` does not)
- `git-delete-merged-branches [-Yes]` (force-deletes the squash-merged ones, because git refuses `branch -d` on them, and says so before asking)
- `rig` (cross-repo work harness — see [hugoforte/rig](https://github.com/hugoforte/rig))
- `rig-install [-Path <dir>] [-Email <address>] [-DataRepo <owner/name>]` (clones the tool, optionally its private data repo as `rig-data` beside it, and runs `rig init`; records a non-default path in `RIG_ROOT`)
- `rig-goto-root`
- `dotfiles-sync` (runs `sync.ps1` in the foreground)
- `dotfiles-tools [-Check]` (runs `install-tools.ps1`; `-Check` reports what is missing and installs nothing)

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
- The merged-branch functions judge a branch merged by content, not by ancestry. `git branch --merged` asks whether the branch tip is reachable from the target, which is false for every squash merge, so on a repo that squashes it reports nothing and merged branches accumulate. `Get-BranchMergeVerdict` returns `ancestor`, `squash` or `no`: ancestry first, then a comparison of the branch's net patch against every patch the target gained since the branch left it. The delete needs that distinction, because git refuses `branch -d` on a branch it cannot reach and those have to go with `-D`
