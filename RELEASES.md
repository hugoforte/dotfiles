# RELEASES

## Unreleased

- Skill secrets: `ai/secrets/` holds SOPS + age encrypted credential files for project-level skills; `deploy-secrets.ps1` decrypts per machine and symlinks them into every checkout; each machine's SSH key is its identity, plus a recovery key in the password manager; `sync.ps1` deploys automatically; `install.sh --check` refuses plaintext under `ai/secrets/`
- `dotfiles-secrets` skill pointing at the procedures
- Skills sync: `ai/install.sh` links every `ai/skills/<name>/` into the Claude Code, Codex and Copilot skills directories
- Vendored Matt Pocock's engineering and productivity skills as `matt-*` (25 skills, MIT, pinned in `ai/licenses/`)
- `review-pr` skill (was a user-level Claude command)
- `rig` skill: points any agent at the cross-repo work harness from any folder
- `ai/install.sh` rewritten: `--check` drift report, `--uninstall`, per-component flags, native symlinks on Git Bash, prerequisites checked per component
- `ai/claude/settings.json` fragment merged into `~/.claude/settings.json` (model, plugins, marketplaces, read-only tool allowlist); `--check` reports settings drift both ways and `--settings-export` copies Claude-side changes back to the repo
- `powershell/sync.ps1` pull-and-relink, `install-sync-task.ps1` scheduled task, `dotfiles-sync` profile function
- `ai/CLAUDE.md` rewritten as my own guidelines; agents trimmed to the seven generic ones with PostHog and Rust sections removed
- Removed inherited MCP server list, hooks, and tool-permissions script
- Colored script output now renders correctly in POSIX `sh`
- Fix `setup.ps1` cloning the upstream fork instead of this repo on a fresh machine
- Vendored `excalidraw-diagram` skill (folder renamed from `excalidraw-diagram-skill-main`)
- `rig`, `rig-install` (with `-DataRepo` for the private data repo) and `rig-goto-root` launcher functions
- AWS profile helpers: `aws-switch-profiles`, `aws-setup-profile`, `aws-view-profile`, `aws-goto-profile-path`
- GitHub Copilot repo instructions and reusable prompts under `.github/`
- `AGENTS.md` and `docs/agents/` config for the engineering skills (GitHub issues, default triage labels, single-context domain docs)
- READMEs rewritten to state what is managed and where it is installed

## 1.0.0 - 2026-03-14

- PowerShell setup script for profile and AWS config symlink setup
- AWS helper functions: `aws-whoami`, `aws-profile`, `aws-switch-profile`
- Git helper function: `git-list-merged-branches`
- Git helper function: `git-delete-merged-branches`
- Git merged-branch operations for local and remote scope
- Symlink-aware helper loading with fallback to `%USERPROFILE%\dotfiles\powershell`
