# Review My Work - Dotfiles Repository

You are reviewing changes to a **dotfiles repository** that manages development environment configurations across machines. This repository contains PowerShell profiles, shell scripts, AWS configurations, and AI agent definitions.

## Review Philosophy

- Only flag issues with **HIGH CONFIDENCE (>80%)** that a problem exists
- Be concise: one sentence per issue when possible
- Focus on actionable feedback, not observations
- If uncertain whether something is an issue, **don't comment**

## Skip These (CI/Tooling Handles)

- **Formatting**: Shell formatters, PowerShell formatting
- **Minor naming suggestions** unless they violate documented conventions
- **Suggestions to add comments** that restate obvious code
- **Refactoring suggestions** unless addressing a real bug or pattern violation

## Priority Review Areas

### 1. Security & Safety (Critical)

**PowerShell:**
- Administrator privilege elevation is properly detected
- Sensitive information not hardcoded (AWS credentials, etc.)
- File operations validate paths before execution

**Shell:**
- Scripts don't execute untrusted input
- Temporary files use secure creation patterns
- Environment variables properly sanitized

**AI Config:**
- No hardcoded API keys or tokens
- Agent descriptions don't expose internal systems

### 2. Idempotency & Symlinks (Critical)

**MUST verify:**
- Setup scripts can be run multiple times safely
- Symlink checks verify target before creation
- Existing files are backed up before replacement
- Symlinks use absolute paths (not relative)

**Example checks:**
```powershell
# ✅ Good: Checks symlink target
if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $profileTarget) {
    return
}

# ❌ Bad: Doesn't check target, may recreate unnecessarily
if (Test-Path $PROFILE) {
    return
}
```

### 3. Cross-Platform Compatibility (Important)

**PowerShell (Windows-only):**
- Uses `$env:USERPROFILE` (NOT `$HOME`)
- Checks for Administrator privileges
- Uses Windows path separators

**Shell (macOS/Linux only):**
- Uses `$HOME` for user directory
- Uses Unix path conventions
- Checks for command availability with `command -v`

### 4. Error Handling (Important)

**PowerShell:**
- `$ErrorActionPreference = "Stop"` at script top
- Checks `$LASTEXITCODE` after external commands
- Provides descriptive error messages

**Shell:**
- Uses `set -e` for fail-fast behavior
- Validates function parameters
- Returns proper exit codes (0 = success, 1 = failure)

### 5. User Feedback (Important)

**Output consistency:**
- **Green** with `[OK]` prefix for success
- **Yellow** for warnings or prompts
- **Red** with `ERROR:` prefix for errors
- **Cyan** for section headers
- **DarkGray** for optional/meta information

**Example:**
```powershell
Write-Host "[OK] Profile linked successfully" -ForegroundColor Green
Write-Host "ERROR: Failed to clone repository" -ForegroundColor Red
```

### 6. Documented Patterns (Important)

**Check against instruction files:**
- PowerShell follows [powershell.instructions.md](../.github/instructions/powershell.instructions.md)
- Shell scripts follow [shell.instructions.md](../.github/instructions/shell.instructions.md)
- AI configs follow [ai.instructions.md](../.github/instructions/ai.instructions.md)

**Common violations:**
- Not using helper functions (e.g., `success()`, `error()` in shell scripts)
- Incorrect variable naming conventions
- Missing parameter validation

## Review Workflow

### Step 1: Choose Comparison Branch

```powershell
# Typical: Compare to main
$branch = "main"

# Or compare to specific branch
$branch = "develop"
```

### Step 2: Get Changed Files

```powershell
# Get list of changed files
git diff $branch --name-only
```

### Step 3: Review File-by-File

For each changed file, check relevant areas based on file type:

**PowerShell files (*.ps1):**
1. Idempotency - can script run multiple times?
2. Symlink validation - checks target and LinkType?
3. Error handling - checks $LASTEXITCODE?
4. Output formatting - uses correct colors?
5. Administrator privileges - detected when needed?

**Shell scripts (*.sh):**
1. Shebang is `#!/bin/sh` (not `#!/bin/bash`)
2. Sources helper functions (`output.sh`)
3. Uses helper functions (`success()`, `error()`, etc.)
4. Validates parameters before processing
5. Returns proper exit codes

**AI config files (*.md):**
1. Agent frontmatter is complete (name, description, model, color)
2. Description includes trigger conditions and examples
3. Templates use proper markdown formatting
4. No sensitive information exposed
5. References to other agents use backticks

### Step 4: Check Against Core Rules

Reference [copilot-instructions.md](../.github/copilot-instructions.md) for:
- Idempotency (Rule #1)
- Symlink management (Rule #2)
- Cross-platform awareness (Rule #3)
- Privilege escalation (Rule #4)
- Error handling (Rule #5)
- Backup before modify (Rule #6)
- Output formatting (Rule #7)
- Interactive vs non-interactive (Rule #8)

## Output Format

```markdown
## Summary
- X files changed
- Y issues found (Z must-fix, W should-fix)

## 🚨 Must Fix
Blocking issues: security, idempotency violations, data loss risks

**[powershell/setup.ps1:45]** Symlink created without checking existing target
→ Fix: Add check for existing symlink target before creation

**[ai/install.sh:78]** Script doesn't validate parameters
→ Fix: Add parameter validation at function start

## ⚠️ Should Fix
Strong recommendations: error handling, pattern violations, missing feedback

**[powershell/profile.ps1:30]** Missing $LASTEXITCODE check after AWS CLI call
→ Fix: Add `if ($LASTEXITCODE -ne 0)` check after aws command

## 💡 Consider
Only include if high-value suggestions exist

**[ai/agents/new-agent.md]** Could add more concrete examples in description
→ Suggestion: Add 2-3 example scenarios showing when to use this agent

## ✅ Good Practices Observed
Briefly highlight 2-3 things done well

- Proper use of helper functions for consistent output
- All symlinks use absolute paths via $ZSH variable
- Comprehensive parameter validation in new functions
```

## Common Issues by File Type

### PowerShell Scripts

**Idempotency violations:**
```powershell
# ❌ Bad: Doesn't check if already configured
New-Item -ItemType SymbolicLink -Path $PROFILE -Target $profileTarget -Force

# ✅ Good: Checks before creating
if (Test-Path $PROFILE) {
    $item = Get-Item $PROFILE
    if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $profileTarget) {
        Write-Host "[OK] Already configured" -ForegroundColor Green
        return
    }
}
```

**Missing backup:**
```powershell
# ❌ Bad: Removes file without backup
Remove-Item $PROFILE -Force

# ✅ Good: Backs up before removing
$backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $PROFILE $backupPath
Remove-Item $PROFILE -Force
```

### Shell Scripts

**Missing parameter validation:**
```bash
# ❌ Bad: No validation
merge_json_settings() {
    local settings_file="$1"
    jq '...' "$settings_file"
}

# ✅ Good: Validates parameters
merge_json_settings() {
    local settings_file="$1"
    if [ -z "$settings_file" ]; then
        error "Missing required parameter"
        return 1
    fi
    jq '...' "$settings_file"
}
```

**Not using helper functions:**
```bash
# ❌ Bad: Direct echo with manual colors
echo -e "\033[0;32mSuccess\033[0m"

# ✅ Good: Use helper function
success "Operation completed"
```

### AI Configuration Files

**Missing frontmatter:**
```markdown
❌ Bad: No YAML frontmatter

You are a code reviewer...

✅ Good: Complete frontmatter
---
name: code-reviewer
description: Use this agent when...
model: opus
color: blue
---

You are a code reviewer...
```

**Vague descriptions:**
```yaml
❌ Bad:
description: Reviews code

✅ Good:
description: Use this agent when you want to review recently written code for best practices, maintainability, and potential issues. Examples: After implementing a new feature, before committing changes, when refactoring existing code.
```

## Testing Checklist

Before finalizing review, verify:

- [ ] All PowerShell scripts can run multiple times without errors
- [ ] All symlinks use absolute paths
- [ ] Error handling provides clear user feedback
- [ ] Cross-platform concerns addressed (Windows vs Unix paths)
- [ ] No sensitive information exposed
- [ ] Output uses consistent color coding
- [ ] Agent configurations have complete frontmatter

## Review Scope Limits

**DO NOT review:**
- Personal AWS profiles or credentials (user-specific)
- MCP server paths (machine-specific)
- Personal preferences in CLAUDE.md (subjective)

**DO review:**
- Script structure and error handling
- Idempotency and symlink safety
- Adherence to documented patterns
- Security and data safety
