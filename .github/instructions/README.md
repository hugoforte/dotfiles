# Copilot Instructions Breakdown

## Structure

```text
.github/
├── copilot-instructions.md
├── instructions/
│   ├── README.md
│   ├── powershell.instructions.md
│   ├── shell.instructions.md
│   └── ai.instructions.md
└── prompts/
    └── review-my-work.prompt.md
```

## Breakdown Philosophy

- copilot-instructions.md defines repo-wide rules (what and why).
- *.instructions.md files define implementation patterns (how).
- Copilot gets both layers: intent and concrete code patterns.

## applyTo Frontmatter

Each instruction file starts with:

```yaml
---
applyTo: "glob/pattern/**/*"
---
```

How it works:

- Pattern matching starts at repo root.
- ** matches nested directories.
- * matches file names.
- Keep globs narrow to avoid pattern bleed across layers.

## Adding New Instruction Files

1. Create .github/instructions/<layer>.instructions.md.
2. Add applyTo frontmatter with precise globs.
3. Extract patterns from real files in that layer.
4. Add examples that already exist in codebase style.
5. Update coverage table below.

## Current Coverage

| applyTo | File | Layer |
|---|---|---|
| powershell/**/*.ps1 | powershell.instructions.md | PowerShell setup/profile/helpers |
| ai/**/*.sh | shell.instructions.md | AI shell scripts |
| ai/**/*.md | ai.instructions.md | AI markdown and agent specs |

## Maintenance Guidance

- Update instructions when conventions change.
- Prefer concise, high-signal patterns over exhaustive prose.
- Keep examples synchronized with current source files.
