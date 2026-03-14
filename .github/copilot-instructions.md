# Dotfiles Repository - GitHub Copilot Instructions

## Project Overview

This repository manages personal development environment configuration with symlink-based setup. It includes PowerShell profile tooling, AWS SSO profile config, and AI assistant config/scripts.

## Technology Stack

| Layer | Technologies | Purpose |
|---|---|---|
| PowerShell | PowerShell 5.1+ | Profile loading, setup automation, helper functions |
| AWS | AWS CLI + SSO config | Account/profile selection and identity checks |
| AI Config | POSIX shell + Markdown | Claude config install, hooks, permissions, agent specs |
| Docs | Markdown | Setup, release, and instruction documentation |

## Repository Structure

```text
dotfiles/
├── .github/
│   ├── copilot-instructions.md
│   ├── instructions/
│   │   ├── README.md
│   │   ├── powershell.instructions.md
│   │   ├── shell.instructions.md
│   │   └── ai.instructions.md
│   └── prompts/
│       └── review-my-work.prompt.md
├── powershell/
│   ├── profile.ps1
│   ├── aws.ps1
│   ├── git.ps1
│   ├── setup.ps1
│   └── README.md
├── aws/
│   ├── config
│   └── README.md
├── ai/
│   ├── CLAUDE.md
│   ├── install.sh
│   ├── validate-settings.sh
│   ├── helpers/
│   └── agents/
├── README.md
└── RELEASES.md
```

## Build & Run Commands

### Prerequisites

- Windows: PowerShell 5.1+, Git, optional AWS CLI, Administrator for symlinks
- macOS/Linux (AI tooling): sh-compatible shell, Git, optional jq, optional Claude CLI

### Setup Commands

```powershell
# Windows setup (repo root)
.\powershell\setup.ps1

# Reload profile after changes
. .\powershell\profile.ps1
list-functions
```

```bash
# AI setup
cd ai && ./install.sh

# Validate Claude settings
cd ai && ./validate-settings.sh
```

## Running Tests

No formal test suite. Use manual validation:

```powershell
. .\powershell\profile.ps1
list-functions
git-list-merged-branches -help
git-delete-merged-branches -help
```

```bash
cd ai
./validate-settings.sh
```

## Configuration Setup

- PowerShell setup links current-user profile and current-user-all-hosts profile to powershell/profile.ps1.
- AWS setup links %USERPROFILE%\\.aws\\config to aws/config.
- AI setup links ~/.claude/CLAUDE.md and ~/.claude/agents/* and merges settings JSON.

## Validation Steps

Before committing:

1. Reload profile and run list-functions.
2. Run git helper help commands.
3. Run ai/validate-settings.sh if AI scripts/settings changed.
4. Verify symlinks still point to expected repo files.
5. Update docs when behavior changes.

## CI/CD Pipeline

No CI pipeline is configured. Validation is local/manual.

## Core Development Rules (Strictly Enforced)

1. Setup scripts must be idempotent.
2. Prefer symlinks over file copies for managed config.
3. Backup regular files before replacing them with symlinks.
4. Keep PowerShell Windows-focused and shell scripts POSIX-focused.
5. Fail fast with clear, color-coded user feedback.
6. Keep destructive operations confirmation-gated by default.
7. When adding behavior, update docs in the same change.

## Naming Conventions

- PowerShell functions: lowercase kebab-case (example: aws-switch-profile).
- Shell scripts: kebab-case file names.
- Shell functions: snake_case.
- Markdown docs: README.md / RELEASES.md at conventional locations.

## Logging / Output Patterns

- PowerShell: Write-Host with color semantics
  - Green: success
  - Yellow: warning/prompt
  - Red: errors
  - Cyan: section/info
  - DarkGray: secondary metadata
- Shell: use helpers from ai/helpers/output.sh (success/warning/error/info/die)

## Dependency Guidelines

- Keep dependencies minimal.
- Shell scripts must check optional tools (for example jq) before use.
- AWS CLI is optional for setup, required for AWS helper execution.
- Claude CLI is optional; AI install should fail clearly when required commands are missing.

## Path-Specific Instructions

| Path | Instruction File | Purpose |
|---|---|---|
| powershell/**/*.ps1 | instructions/powershell.instructions.md | PowerShell implementation patterns |
| ai/**/*.sh | instructions/shell.instructions.md | Shell implementation patterns |
| ai/**/*.md | instructions/ai.instructions.md | AI markdown/agent patterns |
