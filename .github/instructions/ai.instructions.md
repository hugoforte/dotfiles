---
applyTo: "ai/**/*.md"
---

# AI Configuration Development Patterns

This file contains implementation patterns specific to AI agent configuration files (CLAUDE.md and agent definitions).

## Agent Definition Frontmatter

**Pattern:** Every agent file must have YAML frontmatter with metadata.

```yaml
---
name: code-reviewer
description: Use this agent when you want to review recently written code for best practices, maintainability, and potential issues. Examples: After implementing a new feature, before committing changes, when refactoring existing code, or when you want a second pair of eyes on your implementation.
model: opus
color: blue
---
```

**Key points:**
- `name`: kebab-case identifier for the agent
- `description`: When to use this agent, with concrete examples
- `model`: AI model to use (`opus`, `sonnet`, etc.)
- `color`: Visual identifier for the agent (used in UI)

## Agent Description Format

**Pattern:** Provide clear trigger conditions with multiple concrete examples.

```yaml
description: Use this agent when you need to break down complex software features or requirements into actionable implementation stages, create technical specifications, or design system architecture before coding begins. Examples: <example>Context: User wants to add a new authentication system to their web application. user: 'I need to implement OAuth2 authentication with Google and GitHub providers for my Node.js app' assistant: 'I'll use the implementation-planner agent to create a detailed implementation plan for your OAuth2 authentication system.' <commentary>Since the user needs a complex feature planned out, use the implementation-planner agent to break this down into stages with clear deliverables and success criteria.</commentary></example>
```

**Key points:**
- Start with trigger conditions ("when you need to...")
- Include multiple `<example>` blocks
- Each example has: `Context`, `user` query, `assistant` response, `<commentary>`
- Examples should show realistic use cases

## Agent System Prompt Structure

**Pattern:** Structure agent prompts with clear sections and responsibilities.

```markdown
You are a senior code reviewer providing SPECIFIC, ACTIONABLE feedback on code changes. Your role is to identify concrete issues and provide clear guidance on how to fix them, not to teach general principles.

## Core Responsibilities

1. **Correctness** - Logic errors and edge cases
2. **Security** - Input validation vulnerabilities
3. **Maintainability** - Code clarity and confusing logic
4. **Performance** - Obvious inefficiencies
5. **Testing** - Missing test coverage for new functionality

## What You Do NOT Do

- Write code or detailed implementation (delegate to developer)
- Provide general coding guidelines (defer to main system prompt)
- Perform complex refactoring (delegate to developer)
```

**Key points:**
- Start with clear role definition
- Use numbered lists for core responsibilities
- Include "What You Do NOT Do" section to set boundaries
- Use markdown headers for organization

## Severity Level Definitions

**Pattern:** Define clear severity levels for feedback or issues.

```markdown
**Severity Levels:**
- **Critical**: Must fix before merge (blocks deployment/breaks functionality)
- **Important**: Should fix in this PR (impacts code quality or maintainability)
- **Minor**: Consider for future improvement (technical debt)
```

**Key points:**
- Use bold for severity level names
- Provide clear definition with consequences
- Use parenthetical examples for clarification

## Process Workflow Definition

**Pattern:** Use numbered steps with sub-agents for complex workflows.

```markdown
### Workflow Integration Patterns

#### Pattern 1: New Feature Development

1. **Task Assessment** → `task-orchestrator` determines if `implementation-planner` needed
2. **Planning** → `implementation-planner` creates staged plan (if complex)
3. **Test Design** → `unit-test-writer` writes tests for current stage
4. **Implementation** → Write minimal code to pass tests
5. **Quality Check** → `code-reviewer` reviews before commit
6. **Documentation** → `note-taker` documents complex discoveries
7. Repeat steps 3-6 for each stage

#### Pattern 2: Bug Investigation

1. **Initial Debugging** → Try fixing yourself (max 2 attempts)
2. **Systematic Analysis** → `bug-root-cause-analyzer` investigates
3. **Fix Implementation** → Implement the identified solution
4. **Regression Prevention** → `unit-test-writer` adds tests to prevent recurrence
```

**Key points:**
- Use `####` for pattern names
- Number each step clearly
- Use `→` to indicate agent invocation
- Reference agents with backticks
- Provide multiple workflow patterns for different scenarios

## Decision Framework Pattern

**Pattern:** Provide structured decision criteria for agents.

```markdown
## Decision Framework

For implementation decisions, consider these factors in order:

1. **Testability** - Can we easily verify this works?
2. **Maintainability** - Will others understand this in 6 months?
3. **Consistency** - Does this match existing codebase patterns?
4. **Simplicity** - Is this the simplest solution that could work?
5. **Reversibility** - Can we undo this decision if needed?
```

**Key points:**
- Present criteria in priority order
- Use question format for each criterion
- Focus on practical, actionable considerations

## File Path Convention Pattern

**Pattern:** Define standard locations for different types of documentation.

```markdown
## Documentation Framework

### Project Planning

- **Location**: `~/dev/ai/plans/{org}/{repo}/{issue-or-pr-or-branch-name-or-plan-slug}.md`
- **Purpose**: Durable implementation plans for complex features
- **Owner**: `implementation-planner` agent
- **Lifecycle**: Permanent reference for architecture decisions

### Knowledge Capture

- **Location**: `~/dev/ai/notes/`
- **Purpose**: Permanent knowledge about complex discoveries
- **Owner**: `note-taker` agent
- **Trigger**: Non-obvious behaviors, complex debugging insights
```

**Key points:**
- Use bold labels for metadata fields
- Specify exact file paths with variable placeholders
- Indicate which agent owns each documentation type
- Clarify lifecycle expectations

## Template Definition Pattern

**Pattern:** Provide complete templates in fenced code blocks.

````markdown
## Implementation Plan Template

Use this template for all implementation plans:

```markdown
# [Feature Name] Implementation Plan

## Project Overview
- **Feature**: [Brief description and business value]
- **Repository**: [Repo name and branch]
- **Estimated Effort**: [Total time estimate]
- **Risk Level**: [Low/Medium/High with justification]

## Risk Assessment
### Risk 1: [Risk Name]
- **Description**: [What could go wrong]
- **Probability**: [Low/Medium/High]
- **Impact**: [Consequences]
- **Mitigation**: [Prevention strategy]
```
````

**Key points:**
- Use triple backticks for template code blocks
- Use `[Placeholder]` for variable sections
- Include all required sections
- Provide inline guidance for each field

## Agent Trigger Conditions

**Pattern:** Clearly define when to invoke specific agents.

```markdown
### When to Use Which Agent

- **Complex Features (>3 stages or unclear requirements)**: Start with `implementation-planner`
- **Test-First Development**: Use `unit-test-writer` before implementation
- **Debugging Issues**: Use `bug-root-cause-analyzer` after 2 failed attempts
- **Code Quality Checks**: Use `code-reviewer` before commits
- **Complex Discoveries**: Use `note-taker` for non-obvious insights gained through exploration
```

**Key points:**
- Use bold for trigger conditions
- Use backticks for agent names
- Specify thresholds (e.g., "after 2 failed attempts")
- Group by scenario type

## Core Philosophy Section

**Pattern:** Establish guiding principles at the top of configuration.

```markdown
## Philosophy

### Core Beliefs

- **Incremental progress over big bangs** - Small changes that compile and pass tests
- **Learning from existing code** - Study and plan before implementing
- **Pragmatic over dogmatic** - Adapt to project reality
- **Clear intent over clever code** - Be boring and obvious

### Simplicity Means

- Single responsibility per function/class
- Avoid premature abstractions
- No clever tricks - choose the boring solution
- If you need to explain it, it's too complex
```

**Key points:**
- Place philosophy near the top
- Use bold for principle names
- Provide dash-separated explanation
- Include "means" or "implementation" subsections

## Critical Rules and Warnings

**Pattern:** Use bold CRITICAL labels for important constraints.

```markdown
**CRITICAL**: Maximum 2 attempts per issue, then use `bug-root-cause-analyzer` agent.

### 3. When Stuck (After 2 Attempts)

The agent will systematically:

1. **Document what failed** - What you tried, error messages, suspected causes
2. **Research alternatives** - Find similar implementations and approaches
3. **Question fundamentals** - Evaluate abstraction level and problem breakdown
```

**Key points:**
- Use `**CRITICAL**:` prefix for hard rules
- Specify exact thresholds and limits
- Provide clear next actions
- Reference specific agents to invoke

## Code Quality Standards

**Pattern:** Define concrete, checkable standards.

```markdown
### Code Quality

- **Every commit must**:
  - Compile successfully
  - Pass all existing tests
  - Include tests for new functionality
  - Follow project formatting/linting

- **Before committing**:
  - Run formatters/linters
    - In a Rust codebase, run `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo shear`
    - If bin/fmt exists, run it
    - Otherwise, run the formatter for the language
  - Use `code-reviewer` agent for quality check
  - Ensure commit message explains "why"
```

**Key points:**
- Use "must" language for required standards
- Provide language-specific examples
- Include tool commands to run
- Specify fallback behaviors

## Feedback Format Specification

**Pattern:** Define exact output format for agent responses.

```markdown
## Output Format

**[file.cs:123]** Issue description
→ Fix: How to resolve

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

**Key points:**
- Use emoji prefixes for visual clarity
- Show exact format with examples
- Include both path and line number references
- Provide fix guidance with `→` arrow
