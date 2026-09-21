# dotfiles

Personal, symlink-based setup for a Windows development machine: PowerShell profile, AWS CLI config, and AI coding-agent configuration (Claude Code, Codex, Copilot). Clone it on every machine, run two scripts, and edits made anywhere flow through git. A scheduled task keeps each machine pulled and linked.

## What is managed

| Area | Source in repo | Installed to | Installer |
|---|---|---|---|
| PowerShell profile + helper functions | `powershell/` | `$PROFILE` and the all-hosts profile (symlinks) | `powershell/setup.ps1` |
| AWS CLI profiles (SSO, no secrets) | `aws/config` | `%USERPROFILE%\.aws\config` (symlink) | `powershell/setup.ps1` |
| Git identity, incl. per-org email overrides | `git/` | `~/.gitconfig`, `~/.gitconfig-employer` (symlinks) | `powershell/setup.ps1` |
| Agent skills | `ai/skills/<name>/` | `~/.claude/skills`, `~/.codex/skills`, `~/.copilot/skills` (symlinks) | `ai/install.sh` |
| Claude Code global instructions | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` (symlink) | `ai/install.sh` |
| Claude Code sub-agents | `ai/agents/*.md` | `~/.claude/agents/` (symlinks) | `ai/install.sh` |
| Claude Code settings (model, plugins, allowlist) | `ai/claude/settings.json` | merged into `~/.claude/settings.json` | `ai/install.sh` |
| Skill secrets (encrypted with SOPS + age) | `ai/secrets/<skill>/` | `%USERPROFILE%\.agent-secrets\`, then symlinked into every checkout that has the skill | `powershell/deploy-secrets.ps1` |
| Tools and programs a machine needs | `powershell/tools.psd1` | installed via winget and npm | `powershell/install-tools.ps1` |
| Default markdownlint rules | `powershell/markdownlint.jsonc` | passed to `markdownlint-cli2` by the `md-lint` function | none (used in place) |
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

   `setup.ps1` links both PowerShell profiles, `~/.aws/config` and both gitconfigs, backs up any real file it displaces, installs everything in [powershell/tools.psd1](powershell/tools.psd1), and offers to reload the profile. `install-sync-task.ps1` registers the "Dotfiles Sync" task (at logon and every 4 hours). Both are safe to re-run.

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

5. Skill secrets: register the machine as a recipient (see [ai/secrets/README.md](ai/secrets/README.md), "Add a machine"), then:

   ```powershell
   Copy-Item ai\secrets\machine.local.psd1.example ai\secrets\machine.local.psd1
   .\powershell\deploy-secrets.ps1
   ```

## Keeping machines in sync

- Edit files in this repo, commit, push.
- Other machines pull and re-link automatically via the scheduled task, or on demand with `dotfiles-sync` in PowerShell. Symlinked files pick up edits without re-running anything; new files need a re-link, which the sync does.
- Every installer has a report-only mode that changes nothing and exits non-zero if anything is out of sync: `./ai/install.sh --check`, `.\powershell\setup.ps1 -Check`, `.\powershell\deploy-secrets.ps1 -Check` and `dotfiles-tools -Check`. Each reports links that are missing, replaced by a real file, or pointing elsewhere. They answer "is this machine in sync with the repo?" — not "is this code correct?", which is what `tests/` is for.
- Tools are declared in [powershell/tools.psd1](powershell/tools.psd1). Add an entry, commit, push, and every machine installs it on its next sync — the sync only does this work when the manifest has actually changed. Entries marked `Unattended = $false` are skipped by the scheduled task and wait for `dotfiles-tools`; `dotfiles-tools -Check` reports what is missing without installing anything.

## Layout

- [powershell/](powershell/README.md): profile, setup, sync, AWS, Git and rig helper functions
- [aws/](aws/README.md): AWS CLI config
- [ai/](ai/README.md): agent skills, Claude Code config, installer
- [.github/](.github/instructions/README.md): Copilot instructions and reusable prompts
- [tests/](tests/README.md): fixture tests for the parts that can be tested without touching the machine you are on; CI runs them on every pull request
- [CONTEXT.md](CONTEXT.md): the glossary — what "managed", "drift", "checkout" and the rest mean here
- [docs/adr/](docs/adr/): the decisions a reader would otherwise try to undo, and why
- [docs/agents/](docs/agents/): issue tracker, triage labels and domain-doc conventions read by the engineering skills
- [RELEASES.md](RELEASES.md): change log
