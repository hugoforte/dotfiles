# Review My Work - Dotfiles

## Review Philosophy

- Only flag issues with HIGH CONFIDENCE (>80%) that a problem exists
- Be concise: one sentence per issue when possible
- Focus on actionable feedback, not observations
- If uncertain whether something is an issue, don't comment

## Skip These (CI/Tooling Handles)

- Formatting: Prettier, dotnet format, etc.
- Linting: ESLint, analyzers
- Build errors: Compiler catches these
- Test failures: Test runner catches these
- Minor naming suggestions unless they violate conventions
- Suggestions to add comments that restate obvious code
- Refactoring suggestions unless addressing a real bug

## Priority Areas

- Security & Safety (auth, secrets, input validation)
- Correctness Issues (logic errors, resource leaks, null risks)
- Architecture & Patterns (layer violations, missing patterns)
- Test Coverage (new code without tests)

## Workflow Steps

1. Choose comparison branch (`main`, `develop`, or other)
2. Get diff (`git diff <branch> --name-only`)
3. Load relevant standards from instruction files
4. Analyze changes against rules
5. Report findings

## Output Format

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
