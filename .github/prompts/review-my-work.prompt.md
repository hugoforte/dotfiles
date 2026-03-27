---
agent: agent
description: Review work-in-progress changes against a branch and coding standards
---

# Review My Work In Progress

Review the current uncommitted and committed changes, checking for adherence to our coding standards.

## Review Philosophy

- Only flag issues when you have **HIGH CONFIDENCE (>80%)** that a problem exists
- Be concise: one sentence per issue when possible
- Focus on actionable feedback, not observations
- If uncertain whether something is an issue, **don't comment**

## Skip These (CI/Tooling Handles)

Do NOT flag issues that our CI pipeline or tooling already catches:

- **Formatting**: Prettier handles frontend, dotnet format handles backend
- **Linting**: ESLint for frontend, analyzers for .NET
- **Build errors**: `dotnet build` catches these
- **Test failures**: `dotnet test` catches these
- Minor naming suggestions unless they violate conventions
- Suggestions to add comments that restate obvious code
- Refactoring suggestions unless addressing a real bug

## Priority Areas (Focus On These)

### Security & Safety
- Missing `[Authorize]` or `[HasPermission]` attributes
- Hardcoded secrets or credentials
- Missing input validation on external data
- SQL injection or path traversal risks

### Correctness Issues
- Logic errors that could cause exceptions or incorrect behavior
- Resource leaks (connections, streams not disposed)
- Race conditions in async code
- Null reference risks

### Architecture & Patterns
- Services calling other services (not external services)
- Missing transaction wrapping for data modifications
- Layer violations (entities leaked to API, infrastructure in domain)
- API design violations (IActionResult instead of ActionResult<T>, dynamic routes)

### Test Coverage
- New/modified service methods without acceptance tests
- Missing error scenario coverage

## Step 1: Choose Comparison Branch

Ask the user which branch to compare against:

1. **develop** (default) - for feature branches
2. **main** - for release branches
3. **other** - specify a custom branch

If the user doesn't specify, use `develop`.

## Step 2: Get the Changes

Once the branch is confirmed, get the diff:

```bash
git diff <branch> --name-only
```

Then get the full diff for analysis:

```bash
git diff <branch>
```

## Step 3: Discover and Load Standards (Generic)

Load coding standards dynamically so this prompt works in any repository:

1. Always load repo-wide instructions first (if present):
	- `.github/copilot-instructions.md`
	- `AGENTS.md`
	- `COPILOT_INSTRUCTIONS.md`
2. Discover all instruction files in `.github/instructions/` (and subfolders).
3. For each discovered instruction file:
	- Read frontmatter and extract `applyTo` patterns (single pattern or comma-separated list).
	- Normalize patterns and match them against the changed file paths from Step 2.
4. Build a per-file instruction set:
	- Include every instruction file whose `applyTo` matches that changed file.
	- If multiple files match, apply all of them.
5. If an instruction file has no `applyTo`, treat it as global guidance and apply it to all changed files.
6. If no instruction files are found, continue using only repo-wide instructions and the review philosophy in this prompt.

## Step 4: Analyze Changes

For each changed file:
1. Read the file content
2. Check against ALL rules from its matched instruction file(s)
3. Check against repo-wide rules (if available)
4. If no matched instruction files exist, still review using this prompt's priority areas and repo-wide rules

## Step 5: Report Findings

Use this concise format for each issue:

```
**[File:Line]** Brief problem description
→ Why it matters (1 sentence, only if not obvious)
→ Fix: Specific action or code snippet
```

Example:
```
**[AdminController.cs:45]** Returns `Task<IActionResult>` instead of typed result
→ Fix: Change to `Task<ActionResult<UserVM>>`
```

Organize findings by severity (**only report issues where confidence is >80%**):

```
## Summary
- X files changed
- Y issues found (Z must-fix, W should-fix)

## 🚨 Must Fix
Blocking issues: architectural violations, missing auth, security issues, API design violations

**[path/file.cs:123]** Issue description
→ Fix: How to resolve

## ⚠️ Should Fix
Strong recommendations: missing error handling, performance concerns, test pattern violations

## 💡 Consider
Only if high-value: code organization, edge case coverage

## ✅ Good Practices Observed
Briefly highlight 2-3 things done well to reinforce good patterns.
```
