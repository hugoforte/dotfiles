---
agent: agent
description: Generate GitHub Copilot custom instructions for a repository
---

# Generate GitHub Copilot Custom Instructions

Create a comprehensive GitHub Copilot instruction setup for this repository following the structure and philosophy below.

## Structure to Create

```
.github/
├── copilot-instructions.md              # Repo-wide: principles (what & why)
├── instructions/
│   ├── README.md                        # Explains the breakdown philosophy
│   └── [layer].instructions.md          # One per major code layer (how)
└── prompts/
    └── review-my-work.prompt.md         # Self-review workflow
```

## Breakdown Philosophy

| File | Content Type | Examples |
|------|-------------|----------|
| `copilot-instructions.md` | **Principles** - the "what" and "why" | "Controllers MUST wrap data modifications in transactions" |
| `*.instructions.md` | **Implementation** - the "how" with code examples | Actual code patterns used in this repo |

### Why This Separation?

1. **Repo-wide file** defines rules that apply everywhere (architectural boundaries, naming conventions, logging standards)
2. **Path-specific files** show how to implement those rules in each layer with concrete code patterns
3. Copilot gets both context: understands *why* a pattern matters and *how* to apply it

## copilot-instructions.md Should Include

1. **Project Overview** - What this project does (1-2 sentences)
2. **Technology Stack** - Table of layers and technologies
3. **Repository Structure** - Folder tree with descriptions
4. **Build & Run Commands** - Prerequisites, full stack, backend-only, frontend-only
5. **Running Tests** - Test commands with filters
6. **Configuration Setup** - Environment files, secrets setup
7. **Validation Steps** - What to run before committing
8. **CI/CD Pipeline** - Brief mention of workflows
9. **Core Development Rules** - Architectural principles (STRICTLY ENFORCED)
10. **Naming Conventions** - Language-specific patterns
11. **Logging Patterns** - Structured logging examples (if applicable)
12. **Dependency Guidelines** - How to evaluate new dependencies
13. **Path-Specific Instructions** - Table referencing the instruction files

## Path-Specific *.instructions.md Files

Create one file per major layer/project type. Each file needs frontmatter:

```yaml
---
applyTo: "path/to/files/**/*.ext"
---
```

Content should be **implementation patterns with code examples** - the "how", not the "why".

Analyze the codebase to identify:
- Existing patterns and conventions
- Common code structures
- Layer-specific rules

## instructions/README.md Should Include

- Structure diagram
- Breakdown philosophy explanation
- How `applyTo` glob patterns work
- Guide for adding new instructions
- Current coverage table

## review-my-work.prompt.md Should Include

### Review Philosophy

```markdown
- Only flag issues with **HIGH CONFIDENCE (>80%)** that a problem exists
- Be concise: one sentence per issue when possible
- Focus on actionable feedback, not observations
- If uncertain whether something is an issue, **don't comment**
```

### Skip These (CI/Tooling Handles)

```markdown
- **Formatting**: Prettier, dotnet format, etc.
- **Linting**: ESLint, analyzers
- **Build errors**: Compiler catches these
- **Test failures**: Test runner catches these
- Minor naming suggestions unless they violate conventions
- Suggestions to add comments that restate obvious code
- Refactoring suggestions unless addressing a real bug
```

### Priority Areas

- Security & Safety (auth, secrets, input validation)
- Correctness Issues (logic errors, resource leaks, null risks)
- Architecture & Patterns (layer violations, missing patterns)
- Test Coverage (new code without tests)

### Workflow Steps

1. Choose comparison branch (develop/main/other)
2. Get diff (`git diff <branch> --name-only`)
3. Load relevant standards from instruction files
4. Analyze changes against rules
5. Report findings

### Output Format

```markdown
## Summary
- X files changed
- Y issues found (Z must-fix, W should-fix)

## 🚨 Must Fix
Blocking issues: architectural violations, security, API design

**[path/file.cs:123]** Issue description
→ Fix: How to resolve

## ⚠️ Should Fix
Strong recommendations: error handling, performance, test patterns

## 💡 Consider
Only if high-value suggestions exist

## ✅ Good Practices Observed
Briefly highlight 2-3 things done well
```

## Execution Steps

1. **Analyze** - Explore the repository structure and identify all major layers/projects
2. **Read** - Review existing READMEs to understand patterns and conventions
3. **Discover** - Find actual code patterns by reading key files in each layer
4. **Create copilot-instructions.md** - Principles discovered from the codebase
5. **Create path-specific files** - Code patterns with examples from the repo
6. **Create instructions/README.md** - Document the philosophy
7. **Create review-my-work.prompt.md** - Self-review workflow

## Important

- Focus on patterns that are **already established** in the codebase - don't invent new ones
- Extract actual code examples from the repository
- Keep instructions concise and actionable
- Reference existing documentation (READMEs) where available
