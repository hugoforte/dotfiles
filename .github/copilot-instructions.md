# Dotfiles Repository - GitHub Copilot Instructions

## Project Overview

Personal dotfiles for managing development environment configurations across machines, including PowerShell profiles, AWS CLI configurations, and AI assistant (Claude) settings.

## Technology Stack

| Layer | Technologies | Purpose |
|-------|-------------|---------|
| **PowerShell** | PowerShell 5.1+ | Profile management, AWS helper functions |
| **AI Config** | Shell scripts, Markdown | Claude AI agent configuration and installation |
| **AWS** | AWS CLI, SSO | Profile and credential management |
| **Setup** | Shell (bash), PowerShell | Automated environment setup via symlinks |

## Repository Structure

```
dotfiles/
├── .github/
│   ├── copilot-instructions.md          # This file
│   ├── instructions/
│   │   ├── README.md                    # Breakdown philosophy
│   │   ├── powershell.instructions.md   # PowerShell patterns
│   │   ├── shell.instructions.md        # Shell script patterns
│   │   └── ai.instructions.md           # AI configuration patterns
│   └── prompts/
│       └── review-my-work.prompt.md     # Self-review workflow
├── ai/
│   ├── CLAUDE.md                        # Main AI configuration
│   ├── install.sh                       # AI setup script
│   ├── agents/                          # AI agent definitions
│   └── helpers/                         # Shared shell utilities
├── aws/
│   ├── config                           # AWS profiles (symlinked)
│   └── README.md                        # AWS setup documentation
└── powershell/
    ├── profile.ps1                      # PowerShell functions
    ├── setup.ps1                        # Automated setup
    └── README.md                        # PowerShell documentation
```

## Build & Run Commands

### Prerequisites

**Windows:**
- PowerShell 5.1+ (built-in)
- Git
- AWS CLI (optional, for AWS features)
- Administrator privileges (for symlinks)

**macOS/Linux:**
- Bash
- Git
- AWS CLI (optional)
- jq (optional, for JSON merging)

### Setup Commands

**PowerShell (Windows):**
```powershell
# Automated setup (recommended)
.\powershell\setup.ps1

# Manual setup
notepad $PROFILE
# Add: . "$env:USERPROFILE\dotfiles\powershell\profile.ps1"
& $PROFILE
```

**Shell (macOS/Linux):**
```bash
# AI configuration setup
cd ai && ./install.sh

# Uninstall AI configuration
cd ai && ./install.sh --uninstall
```

### AWS Helper Functions

```powershell
list-functions          # Show all available functions
aws-whoami              # Display current AWS identity
aws-profile production  # Switch to specific profile
aws-switch-profile      # Interactive profile switcher
```

## Running Tests

No formal test suite. Validation is manual:

```powershell
# PowerShell: Verify profile loaded
list-functions

# Verify AWS config symlinked
Test-Path ~\.aws\config
(Get-Item ~\.aws\config).LinkType  # Should be "SymbolicLink"
```

```bash
# Shell: Validate AI configuration
cd ai && ./validate-settings.sh
```

## Configuration Setup

### PowerShell

1. Run `setup.ps1` (requires Administrator)
2. Creates symlink: `$PROFILE` → `dotfiles/powershell/profile.ps1`
3. Creates symlink: `~/.aws/config` → `dotfiles/aws/config`
4. Backs up existing files with timestamp

### AI Configuration

1. Run `ai/install.sh`
2. Creates symlinks:
   - `~/.claude/CLAUDE.md` → `dotfiles/ai/CLAUDE.md`
   - `~/.claude/agents/*` → `dotfiles/ai/agents/*`
3. Merges MCP server configurations into `~/.claude/settings.json`

## Validation Steps

**Before Committing:**

1. **PowerShell:** Test all functions in `list-functions`
2. **Shell:** Run `./validate-settings.sh` in `ai/` directory
3. **Verify symlinks:** Ensure symlinks point to correct targets
4. **Documentation:** Update READMEs for any new functions or configurations

**After Pull:**

```powershell
# PowerShell
cd "$env:USERPROFILE\dotfiles"
git pull
& $PROFILE  # Reload profile
```

```bash
# Shell
cd ~/.dotfiles
git pull
cd ai && ./install.sh  # Re-run to update symlinks
```

## CI/CD Pipeline

No automated CI/CD. Manual verification via setup scripts.

---

## Core Development Rules (STRICTLY ENFORCED)

### 1. Idempotency

**RULE:** All setup scripts MUST be idempotent - safe to run multiple times without side effects.

**Why:** Users may re-run setup scripts after pulling updates or on errors.

**Implementation:**
- Check if symlinks exist before creating
- Detect if files are already configured
- Skip operations that are already complete
- Back up existing files before overwriting

**Example (PowerShell):**
```powershell
if (Test-Path $PROFILE) {
    $item = Get-Item $PROFILE
    if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $profileTarget) {
        Write-Host "[OK] Already configured" -ForegroundColor Green
        return
    }
}
```

### 2. Symlink Management

**RULE:** Use symbolic links for configuration files, NOT copies.

**Why:** Keeps dotfiles in sync via git; changes propagate immediately.

**Implementation:**
- PowerShell: `New-Item -ItemType SymbolicLink`
- Shell: `ln -sf`
- Always verify symlink target before creating
- Backup existing regular files before replacing with symlinks

**Required checks:**
```powershell
if ((Get-Item $path).LinkType -ne "SymbolicLink") {
    # Backup and replace
}
```

### 3. Cross-Platform Awareness

**RULE:** PowerShell scripts are Windows-only; shell scripts are macOS/Linux-only.

**Why:** Different platforms have different setup requirements.

**DO:**
- Use `$env:USERPROFILE` for Windows user directory
- Use `$HOME` for Unix-like systems
- Test paths exist before using

**DON'T:**
- Mix PowerShell and shell in the same script
- Assume paths like `/usr/local` exist on Windows

### 4. Privilege Escalation

**RULE:** Detect and request Administrator/sudo privileges when needed.

**Why:** Symlinks on Windows require Administrator; Unix systems may need sudo.

**PowerShell:**
```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command & { ... }" -Verb RunAs
    exit
}
```

### 5. Error Handling

**RULE:** Fail fast with clear error messages.

**Why:** Setup scripts must inform users exactly what failed.

**PowerShell:**
```powershell
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to clone repository" -ForegroundColor Red
    exit 1
}
```

**Shell:**
```bash
set -e  # Exit on error
die() {
    error "$1"
    exit 1
}
```

### 6. Backup Before Modify

**RULE:** Always backup existing files before replacing with symlinks.

**Why:** Users may have custom configurations that should not be lost.

**PowerShell:**
```powershell
if ((Test-Path $PROFILE) -and (Get-Item $PROFILE).LinkType -ne "SymbolicLink") {
    $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $PROFILE $backupPath
    Write-Host "[OK] Backup saved to: $backupPath" -ForegroundColor Green
}
```

### 7. Output Formatting

**RULE:** Use consistent color-coded output for user feedback.

**Why:** Users need clear visual feedback on what's happening.

**Colors:**
- **Green:** Success (`[OK]` prefix)
- **Yellow:** Warnings or user prompts
- **Red:** Errors
- **Blue/Cyan:** Informational headings
- **DarkGray:** Optional/cancellation messages

**PowerShell:**
```powershell
Write-Host "[OK] Operation successful" -ForegroundColor Green
Write-Host "WARNING: File exists" -ForegroundColor Yellow
Write-Host "ERROR: Operation failed" -ForegroundColor Red
```

**Shell:**
```bash
success "Operation successful"  # Green with ✓
warning "File exists"            # Yellow
error "Operation failed"         # Red
```

### 8. Interactive vs Non-Interactive

**RULE:** Setup scripts should support both interactive and forced modes.

**Why:** Automation may require non-interactive execution.

**PowerShell:**
```powershell
param([switch]$Force)

if (!$Force) {
    $confirm = Read-Host "Overwrite existing? (y/n)"
    if ($confirm -ne "y") { return }
}
```

---

## Naming Conventions

### PowerShell Functions

- **Pattern:** `verb-noun` (lowercase, hyphenated)
- **Examples:** `aws-whoami`, `aws-switch-profile`, `list-functions`
- **Verbs:** Standard PowerShell verbs when applicable (`Get`, `Set`, etc.), otherwise descriptive action verbs

### Shell Scripts

- **Pattern:** `kebab-case.sh`
- **Examples:** `install.sh`, `validate-settings.sh`, `json-settings.sh`
- **Functions:** `snake_case`

### Variables

**PowerShell:**
- **Parameters:** `$PascalCase`
- **Local variables:** `$camelCase`
- **Environment variables:** `$env:UPPERCASE`

**Shell:**
- **Local variables:** `snake_case`
- **Environment variables:** `SCREAMING_SNAKE_CASE`
- **Readonly/constants:** `SCREAMING_SNAKE_CASE`

### Files and Directories

- **Config files:** UPPERCASE or lowercase (e.g., `CLAUDE.md`, `config`)
- **Documentation:** `README.md` (always uppercase)
- **Scripts:** lowercase with extension (`.ps1`, `.sh`)

---

## Dependency Guidelines

### Evaluating New Dependencies

**PowerShell:**
- Prefer built-in cmdlets over external tools
- Only add modules if functionality is critical
- Document installation steps in README

**Shell:**
- Core utilities should work without dependencies
- Optional features can require `jq`, `curl`, etc.
- Detect missing dependencies and provide clear instructions

**Example:**
```bash
if ! command -v jq > /dev/null 2>&1; then
    warning "jq not found - JSON merging skipped"
    info "Install jq and re-run to enable this feature"
    return 1
fi
```

### AWS CLI

- Treat as optional dependency
- Functions should gracefully fail if AWS CLI not installed
- Document SSO login requirements

---

## Path-Specific Instructions

For detailed implementation patterns specific to each layer, refer to:

| Path | Instruction File | Description |
|------|-----------------|-------------|
| `powershell/**/*.ps1` | [instructions/powershell.instructions.md](instructions/powershell.instructions.md) | PowerShell function patterns, profile management |
| `ai/**/*.sh` | [instructions/shell.instructions.md](instructions/shell.instructions.md) | Shell script patterns, symlink management |
| `ai/**/*.md` | [instructions/ai.instructions.md](instructions/ai.instructions.md) | AI agent configuration, CLAUDE.md patterns |
