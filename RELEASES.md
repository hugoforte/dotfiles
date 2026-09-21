# RELEASES

## Unreleased

- `CONTEXT.md` and `docs/adr/`, which `AGENTS.md` has been pointing agents at since before either existed: a glossary of what this repo means by managed, unmanaged, drift, check, checkout, marker and the rest, and five ADRs for the decisions a reader would otherwise try to undo — symlinks rather than copies, `cmd /c mklink` rather than `New-Item` (and why `setup.ps1` still elevates), back-up-then-link, windows-only CI, and plain `sh` rather than `bats`
- One managed link: `powershell/managed-link.ps1` (`Set-ManagedLink` / `Test-ManagedLink` / `Remove-ManagedLink`) replaces the probe-backup-link block that was written out four times in `setup.ps1` plus a fifth in `deploy-secrets.ps1`, and `aws-setup-profile` now makes the same link instead of copying over it with a file that goes stale. One backup policy replaces four — back up, then link, with the location a parameter so `deploy-secrets.ps1` keeps displaced plaintext out of a checkout — and `ai/install.sh`'s `link()` follows it too instead of refusing. `setup.ps1` gains the `-Check` it was the only managed state to lack. The module uses `cmd /c mklink`, which works unelevated under Developer Mode, where Windows PowerShell 5.1's `New-Item -ItemType SymbolicLink` does not; `setup.ps1` still elevates, but for `install-tools.ps1`'s machine-scope winget installs, which is what that was actually earning
- Scripts return a result instead of only printing one: `powershell/output.ps1` holds the one reporting vocabulary (`Say`/`Ok`/`Change`/`Warn`/`Todo`/`Fail`) and the result object of counts and messages; `install-tools.ps1 -PassThru` and `deploy-secrets.ps1 -PassThru` hand it to a caller, so `sync.ps1` logs what a run actually did rather than the hardcoded "ok" it logged for runs that warned; `sync.log` no longer collects `ai/install.sh`'s ANSI escapes; `deploy-secrets.ps1` counts drift explicitly instead of inside `Warn`; `ai/helpers/output.sh` and `check-encrypted.sh` use the same prefixes
- Settings reconciliation module `ai/helpers/settings-reconcile.sh` (replaces `json-settings.sh`): one managed-key spec behind all three directions, so `--check` now fails on repo-declared entries missing from the live file, `--settings-export` writes back only the managed leaf paths instead of whole top-level keys, and `validate-settings.sh` shares the same jq and JSON-validity precondition
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
