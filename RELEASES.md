# RELEASES

## Unreleased

- Skills sync: `ai/install.sh --skills-only` links every `ai/skills/<name>/` into the Claude Code, Codex and Copilot skills directories
- `install.sh` checks prerequisites per component, enables native symlinks on Git Bash, and only validates settings when it changed them
- Colored script output now renders correctly in POSIX `sh`
- Fix `setup.ps1` cloning the upstream fork instead of this repo on a fresh machine
- Vendored `excalidraw-diagram` skill (folder renamed from `excalidraw-diagram-skill-main`)
- `rig` and `rig-goto-root` launcher functions
- AWS profile helpers: `aws-switch-profiles`, `aws-setup-profile`, `aws-view-profile`, `aws-goto-profile-path`
- GitHub Copilot repo instructions and reusable prompts under `.github/`
- `AGENTS.md` and `docs/agents/` config for the engineering skills (GitHub issues, default triage labels, single-context domain docs)
- READMEs rewritten to state what is managed, where it is installed, and what is inherited

## 1.0.0 - 2026-03-14

- PowerShell setup script for profile and AWS config symlink setup
- AWS helper functions: `aws-whoami`, `aws-profile`, `aws-switch-profile`
- Git helper function: `git-list-merged-branches`
- Git helper function: `git-delete-merged-branches`
- Git merged-branch operations for local and remote scope
- Symlink-aware helper loading with fallback to `%USERPROFILE%\dotfiles\powershell`
