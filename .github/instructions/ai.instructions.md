---
applyTo: "ai/**/*.md"
---

# AI Configuration Development Patterns

This file captures markdown patterns used by AI configuration docs and agent specs.

## Agent Frontmatter Pattern

Agent files under `ai/agents/` use YAML frontmatter.

```yaml
---
name: task-orchestrator
description: Use this agent to determine the optimal agent workflow...
model: sonnet
color: orange
---
```

Key points:

- Keep `name` in kebab-case.
- Keep descriptions action-oriented and include example scenarios.
- Include model and color in every agent file.

## Agent Body Structure Pattern

Use clear markdown sections with ordered workflows.

```markdown
## Task Classification Framework
## Agent Workflow Recommendations
## Decision Matrix
## Output Format
```

Key points:

- Prefer short section headers.
- Use numbered workflow steps for handoff order.
- Keep output schema explicit when file defines reviewer/planner behavior.

## CLAUDE.md Pattern

`ai/CLAUDE.md` loads in every Claude Code session, so every line must change behaviour against the model's and Claude Code's defaults.

Key points:

- Keep only rules the model would not follow on its own; cut maxims and generic advice.
- Put guidance for one kind of file in `ai/rules/` with a `paths:` filter, and guidance for one repo in that repo.
- State a hard limit as "never X, because Z"; leave out capitals and emphasis, which make a rule over-apply.
- Avoid project-specific external references unless they are intentional and maintained.

## Markdown Conventions

- Use headings and short bullet lists.
- Use fenced code blocks for command examples.
- Keep prose concise; prefer actionable statements over narrative.
- Keep file names conventional: `README.md`, `CLAUDE.md`, `RELEASES.md`.
