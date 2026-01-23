# GitHub Copilot Instructions - Structure Overview

This directory contains the GitHub Copilot custom instructions for the dotfiles repository, organized to provide both high-level principles and detailed implementation patterns.

## Directory Structure

```
.github/
├── copilot-instructions.md              # Repo-wide principles
├── instructions/
│   ├── README.md                        # This file
│   ├── powershell.instructions.md       # PowerShell patterns
│   ├── shell.instructions.md            # Shell script patterns
│   └── ai.instructions.md               # AI configuration patterns
└── prompts/
    └── review-my-work.prompt.md         # Self-review workflow
```

## Breakdown Philosophy

We split instructions into two complementary layers:

### Layer 1: Principles (copilot-instructions.md)

**What it contains:**
- Project overview and structure
- Core development rules (the "MUST" and "SHOULD" guidelines)
- Naming conventions
- Architectural principles
- Cross-cutting concerns (error handling, output formatting, etc.)

**Why it's repo-wide:**
These principles apply everywhere in the codebase regardless of file type. When working on any file, Copilot needs to understand the overall architecture and non-negotiable rules.

**Example:**
```
RULE: All setup scripts MUST be idempotent - safe to run multiple times without side effects.
```

### Layer 2: Implementation Patterns (instructions/*.instructions.md)

**What it contains:**
- Actual code patterns from the repository
- Concrete examples showing HOW to implement the principles
- Language-specific idioms and conventions
- Common code structures and templates

**Why it's path-specific:**
Different parts of the codebase use different languages and patterns. PowerShell scripts have different idioms than shell scripts, and AI configuration files follow their own conventions.

**Example:**
```powershell
# PowerShell: Check if symlink exists before creating
if (Test-Path $PROFILE) {
    $item = Get-Item $PROFILE
    if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $profileTarget) {
        Write-Host "[OK] Already configured" -ForegroundColor Green
        return
    }
}
```

## How applyTo Glob Patterns Work

Each instruction file has frontmatter that specifies which files it applies to:

```yaml
---
applyTo: "powershell/**/*.ps1"
---
```

**Glob pattern rules:**
- `**` matches any directory depth
- `*` matches any filename
- Patterns are matched from the repository root
- Multiple extensions: `**/*.{js,ts}`

**Current coverage:**

| Pattern | Instruction File | Description |
|---------|-----------------|-------------|
| `powershell/**/*.ps1` | [powershell.instructions.md](powershell.instructions.md) | PowerShell scripts and setup |
| `ai/**/*.sh` | [shell.instructions.md](shell.instructions.md) | Shell scripts for AI configuration |
| `ai/**/*.md` | [ai.instructions.md](ai.instructions.md) | AI agent configuration files |

## Why This Structure Works

### Problem: Copilot needs both "what" and "how"

**Just principles:** Copilot knows the rules but not how to apply them in specific contexts.
- "Use idempotent patterns" → *But how do I check if a symlink exists in PowerShell?*

**Just patterns:** Copilot sees code examples but doesn't understand why they matter.
- Sees symlink checking code → *Why is this check necessary?*

**Both together:** Copilot understands the principle AND has concrete code patterns.
- Principle: "Scripts must be idempotent"
- Pattern: "Use `Get-Item $path).LinkType -eq "SymbolicLink"` to check symlinks"
- Result: Copilot writes idempotent code using the correct PowerShell idioms

## Adding New Instructions

### When to add a new instruction file

Create a new `*.instructions.md` file when:
- You have a new major code layer (e.g., adding Python scripts)
- File type has distinct patterns that don't fit existing files
- Language-specific conventions differ significantly

### Steps to add new instruction file

1. **Create file:** `.github/instructions/[layer].instructions.md`

2. **Add frontmatter:**
   ```yaml
   ---
   applyTo: "path/**/*.ext"
   ---
   ```

3. **Extract patterns from codebase:**
   - Find 3-5 representative files in that layer
   - Identify common patterns and structures
   - Document with actual code examples from the repo

4. **Update this README:**
   - Add entry to "Current coverage" table
   - Update directory structure if needed

5. **Update copilot-instructions.md:**
   - Add entry to "Path-Specific Instructions" table

### Pattern extraction checklist

When documenting patterns, include:
- ✅ Actual code from the repository
- ✅ Comments explaining WHY the pattern exists
- ✅ Key points highlighting critical details
- ✅ Multiple examples showing variations
- ❌ Made-up code that doesn't exist in the repo
- ❌ General programming advice (belongs in copilot-instructions.md)

## Maintenance Guidelines

### When to update

**Update instruction files when:**
- Adding new functions or scripts with novel patterns
- Refactoring code introduces new conventions
- Identifying anti-patterns that should be avoided
- Team agrees on new coding standards

**Don't update for:**
- Minor bug fixes that don't change patterns
- Adding comments or documentation
- Changes that don't introduce new patterns

### Review process

Before committing instruction changes:
1. Verify examples are actual code from the repository
2. Check that glob patterns match intended files
3. Ensure principles and patterns are aligned
4. Test by asking Copilot to generate code following new patterns

## Using Instructions Effectively

### For developers

**When writing new code:**
- Copilot will automatically apply both repo-wide principles and path-specific patterns
- If Copilot suggests code that violates principles, check if instructions need updating

**When code reviewing:**
- Reference instruction files for agreed-upon patterns
- Check that new code follows documented conventions

### For AI agents

**Implementation agents:**
- Read `copilot-instructions.md` for overall architecture
- Reference specific `*.instructions.md` for code patterns
- Follow templates and examples exactly

**Review agents:**
- Use principles to validate architectural compliance
- Use patterns to check language-specific idioms
- Flag deviations from documented standards

## Examples of Good vs. Bad Instruction Content

### ✅ Good: Specific Pattern with Context

```markdown
## Symlink Creation with Idempotency

**Pattern:** Check existing symlinks before creating, backup regular files.

```powershell
if (Test-Path $PROFILE) {
    $item = Get-Item $PROFILE
    if ($item.LinkType -eq "SymbolicLink" -and $item.Target -eq $profileTarget) {
        Write-Host "[OK] Already configured" -ForegroundColor Green
        return
    }
}
```

**Key points:**
- Use `Get-Item` to inspect `LinkType` property
- Compare `Target` to expected path for idempotency
- Provide user feedback with color-coded messages
```

**Why it's good:**
- Shows actual code from the repository
- Explains the principle (idempotency)
- Provides implementation details (use `Get-Item`, check `LinkType`)
- Highlights key points specific to this codebase

### ❌ Bad: Generic Advice

```markdown
## Working with Symlinks

Symlinks are symbolic links that point to other files. In PowerShell, you can create them with `New-Item -ItemType SymbolicLink`. Make sure to check if files exist before creating symlinks.
```

**Why it's bad:**
- No actual code examples
- Doesn't show the specific pattern used in this repo
- Generic advice that applies to any PowerShell code
- Doesn't explain WHY we check symlinks (idempotency principle)

## FAQ

**Q: Should all rules go in copilot-instructions.md?**
A: Yes, if they apply across the entire repository. Path-specific files should only contain implementation patterns.

**Q: Can I have examples in copilot-instructions.md?**
A: Yes, but keep them brief. Full code patterns belong in path-specific files.

**Q: What if a pattern applies to multiple file types?**
A: Document it in each relevant instruction file. Repetition is okay for clarity.

**Q: How detailed should code examples be?**
A: Show enough context to understand the pattern (usually 5-15 lines). Include key surrounding code.

**Q: Should I document every function?**
A: No. Document *patterns* that are reused. One example represents many similar functions.

## Additional Resources

- [copilot-instructions.md](../copilot-instructions.md) - Repo-wide principles
- [review-my-work.prompt.md](../prompts/review-my-work.prompt.md) - Self-review workflow
- Repository README files - Project-specific documentation
