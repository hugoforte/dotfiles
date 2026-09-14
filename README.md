# dotfiles

Personal, symlink-based setup for a Windows development machine: PowerShell profile, AWS CLI config, and AI coding-agent configuration (Claude Code, Codex, Copilot). Clone it on every machine, run the two setup scripts, and edits made anywhere flow through git.

Forked from [haacked/dotfiles](https://github.com/haacked/dotfiles). The `ai/` folder still carries some of the upstream author's project-specific content; see [ai/README.md](ai/README.md#inherited-from-upstream).

## What is managed

| Area | Source in repo | Installed to | Installer |
|---|---|---|---|
| PowerShell profile + helper functions | `powershell/` | `$PROFILE` and the all-hosts profile (symlinks) | `powershell/setup.ps1` |
| AWS CLI profiles (SSO, no secrets) | `aws/config` | `%USERPROFILE%\.aws\config` (symlink) | `powershell/setup.ps1` |
| Agent skills | `ai/skills/<name>/` | `~/.claude/skills`, `~/.codex/skills`, `~/.copilot/skills` (symlinks) | `ai/install.sh --skills-only` |
| Claude Code global instructions | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` (symlink) | `ai/install.sh` |
| Claude Code sub-agents | `ai/agents/*.md` | `~/.claude/agents/` (symlinks) | `ai/install.sh` |
| Claude Code MCP servers, hooks, permissions | `ai/install.sh`, `ai/configure-tool-permissions.sh` | `~/.claude/settings.json`, `claude mcp` | `ai/install.sh` |
| Copilot repo instructions and prompts | `.github/` | used in place by GitHub Copilot | none |
| Engineering-skill config for this repo | `AGENTS.md`, `docs/agents/` | used in place by Claude Code | none |

## Quick start (new Windows machine)

1. Clone the repo anywhere, for example `C:\source\dotfiles`.
2. PowerShell profile and AWS config:

   ```powershell
   cd C:\source\dotfiles\powershell
   .\setup.ps1
   ```

   Elevates itself (symlinks), links both PowerShell profiles and `~/.aws/config`, backs up any regular files it replaces, and offers to reload the profile. Safe to re-run.

3. Agent skills, from Git Bash:

   ```sh
   ./ai/install.sh --skills-only
   ```

   Needs Windows Developer Mode (Settings > System > For developers) or an elevated Git Bash so native symlinks can be created. Run the full `./ai/install.sh` only after reviewing the inherited Claude config described in `ai/README.md`.

## Keeping machines in sync

- Edit files in this repo, commit, push.
- On the other machine: `git pull`, then re-run `setup.ps1` or `install.sh` if new files were added. Symlinked files pick up edits without re-running anything.

## Layout

- [powershell/](powershell/README.md): profile, setup script, AWS, Git and rig helper functions
- [aws/](aws/README.md): AWS CLI config
- [ai/](ai/README.md): agent skills, Claude Code config, installer
- [.github/](.github/instructions/README.md): Copilot instructions and reusable prompts
- [docs/agents/](docs/agents/): issue tracker, triage labels and domain-doc conventions read by the engineering skills
- [RELEASES.md](RELEASES.md): change log
