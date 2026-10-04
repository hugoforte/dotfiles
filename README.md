# dotfiles

Personal, symlink-based setup for a Windows development machine: PowerShell profile, AWS CLI config, and AI coding-agent configuration (Claude Code, Codex, Copilot). Clone it on every machine, run two scripts, and edits made anywhere flow through git. A scheduled task keeps each machine pulled and linked.

## What is managed

| Area | Source in repo | Installed to | Installer |
|---|---|---|---|
| PowerShell profile + helper functions | `powershell/` | `$PROFILE` and the all-hosts profile (symlinks) | `powershell/setup.ps1` |
| AWS CLI profiles (SSO, no secrets) | an overlay's `aws/config` | `%USERPROFILE%\.aws\config` (symlink) | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Git identity | `git/` | `~/.gitconfig` (symlink) | `powershell/setup.ps1` |
| Per-org git identities and other overlay git config | an overlay's `git/gitconfig` | included by `~/.gitconfig-overlays` (generated) | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Agent skills | `ai/skills/<name>/`, here or in an overlay | `~/.claude/skills`, `~/.codex/skills`, `~/.copilot/skills` (symlinks) | `ai/install.sh` |
| Bruno API collections | an overlay's `bruno/<collection>/` | `~/bruno/<collection>` (symlinks) | `ai/install.sh` |
| Claude Code global instructions | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` (symlink) | `ai/install.sh` |
| Claude Code sub-agents | `ai/agents/*.md` | `~/.claude/agents/` (symlinks) | `ai/install.sh` |
| Claude Code settings (model, plugins, allowlist) | `ai/claude/settings.json` | merged into `~/.claude/settings.json` | `ai/install.sh` |
| Skill secrets (encrypted with SOPS + age) | `ai/secrets/<skill>/`, here or in an overlay | `%USERPROFILE%\.agent-secrets\`, then symlinked into every checkout that has the skill (shipped skills read them in place) | `powershell/deploy-secrets.ps1` |
| Commands for every shell, agents' included (`md-lint`) | `bin/` | the user PATH | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Tools and programs a machine needs | `powershell/tools.psd1` | installed via winget, npm and GitHub releases | `powershell/install-tools.ps1` |
| Default markdownlint rules | `powershell/markdownlint.jsonc` | passed to `markdownlint-cli2` by `bin/md-lint` | none (used in place) |
| Automatic pull-and-relink | `powershell/sync.ps1` | Windows scheduled task "Dotfiles Sync" | `powershell/install-sync-task.ps1` |
| Copilot repo instructions and prompts | `.github/` | used in place by GitHub Copilot | none |
| Engineering-skill config for this repo | `AGENTS.md`, `docs/agents/` | used in place by Claude Code | none |

## Quick start (new Windows machine)

1. Turn on Developer Mode (Settings > System > For developers) so symlinks work without elevation.
2. Clone the repo anywhere, for example `C:\source\dotfiles`.
3. PowerShell profile and AWS config:

   ```powershell
   cd C:\source\dotfiles\powershell
   .\setup.ps1
   .\install-sync-task.ps1
   ```

   `setup.ps1` links both PowerShell profiles, `~/.aws/config` (when a source exists) and `~/.gitconfig`, writes `~/.gitconfig-overlays`, backs up any real file it displaces, installs everything in [powershell/tools.psd1](powershell/tools.psd1), and offers to reload the profile. `install-sync-task.ps1` registers the "Dotfiles Sync" task (at logon and every 4 hours). Both are safe to re-run.

   `setup.ps1` elevates itself, but **not for the symlinks** — those work unelevated once Developer Mode is on. It elevates so winget installs the manifest machine-wide; unelevated it would quietly fall back to `--scope user`. See [ADR 0002](docs/adr/0002-mklink-not-new-item.md).

   To see what it would do without doing any of it:

   ```powershell
   .\setup.ps1 -Check
   ```

4. AI tooling, from Git Bash:

   ```sh
   ./ai/install.sh
   ./ai/install.sh --check
   ```

5. Private configuration: register the machine as a SOPS recipient in each overlay (see [ai/secrets/README.md](ai/secrets/README.md), "Add a machine"), then add the overlay repo:

   ```powershell
   .\powershell\install-overlays.ps1 -Repo <owner>/<private-repo>
   ```

   It clones the repo beside this one, lists its overlays in `ai\secrets\machine.local.psd1` (created from the example if missing; check its `SearchRoots`), and runs `sync.ps1` to apply them.

## Private configuration: overlays

This repo holds nothing private. Anything that is, such as employer AWS accounts, a work email, or skill secrets whose key names say too much, lives in an **overlay**: a directory in a private repo, laid out like this repo's root. A machine lists its overlays in the git-ignored `ai/secrets/machine.local.psd1`, so no tracked file here names one. One private repo may hold several overlays, one per audience, so an employer's overlay can later move to a repo the employer owns.

What an overlay can supply, and how:

- `ai/secrets/registry.psd1` and `ai/secrets/<skill>/`: merged with every other registry; a skill id may be registered only once.
- `ai/skills/<name>/`: linked beside this repo's skills by `ai/install.sh`, for a skill whose text names something private; a skill name may be shipped from only one place.
- `bruno/<collection>/`: linked into `~/bruno` by `ai/install.sh`, so Bruno opens every overlay's collections from one home; a collection name may be shipped from only one place.
- `aws/config`: linked to `~/.aws/config`; only one source across this repo and all overlays.
- `git/gitconfig`: included, in overlay order, by the generated `~/.gitconfig-overlays`.

The sync task pulls each overlay repo and re-applies all of these, so a change pushed to an overlay reaches every machine that lists it. Skills are linked by `ai/install.sh`, which the sync runs before it pulls the overlays, so an overlay's skill change lands one sync later. `install-overlays.ps1` is idempotent; re-run it when an overlay repo gains an overlay.

## Keeping machines in sync

- Edit files in this repo, commit, push.
- Other machines pull and re-link automatically via the scheduled task, or on demand with `dotfiles-sync` in PowerShell. Symlinked files pick up edits without re-running anything; new files need a re-link, which the sync does.
- Every installer has a report-only mode that changes nothing and exits non-zero if anything is out of sync: `./ai/install.sh --check`, `.\powershell\setup.ps1 -Check`, `.\powershell\deploy-secrets.ps1 -Check` and `dotfiles-tools -Check`. Each reports links that are missing, replaced by a real file, or pointing elsewhere. They answer "is this machine in sync with the repo?" — not "is this code correct?", which is what `tests/` is for.
- Tools are declared in [powershell/tools.psd1](powershell/tools.psd1). Add an entry, commit, push, and every machine installs it on its next sync — the sync only does this work when the manifest, or the machine's options, have actually changed. Entries marked `Unattended = $false` are skipped by the scheduled task and wait for `dotfiles-tools`; `dotfiles-tools -Check` reports what is missing without installing anything.
- Optional tools install only on machines that ask for them. An entry with `Optional = 'openwhispr'` belongs to that option; list the name under `OptionalTools` in `ai/secrets/machine.local.psd1` and run `dotfiles-tools` to install it, its first-run step included. Machines that don't list it are told it is available. A machine without skill secrets can write that file just for `OptionalTools`: the sync deploys secrets only when it also declares `SearchRoots`.

## Layout

- [powershell/](powershell/README.md): profile, setup, sync, AWS, Git and rig helper functions
- [aws/](aws/README.md): how the AWS CLI config is supplied
- [ai/](ai/README.md): agent skills, Claude Code config, installer
- [.github/](.github/instructions/README.md): Copilot instructions and reusable prompts
- [tests/](tests/README.md): fixture tests for the parts that can be tested without touching the machine you are on; CI runs them on every pull request
- [CONTEXT.md](CONTEXT.md): the glossary — what "managed", "drift", "checkout" and the rest mean here
- [docs/adr/](docs/adr/): the decisions a reader would otherwise try to undo, and why
- [docs/agents/](docs/agents/): issue tracker, triage labels and domain-doc conventions read by the engineering skills
- [RELEASES.md](RELEASES.md): change log
