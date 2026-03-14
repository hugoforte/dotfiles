---
applyTo: "ai/**/*.sh"
---

# Shell Script Development Patterns

This file captures implementation patterns for AI shell scripts.

## Script Foundation Pattern

```bash
#!/bin/sh

export ZSH=$HOME/.dotfiles
. $ZSH/ai/helpers/output.sh
. $ZSH/ai/helpers/json-settings.sh
```

Key points:

- Use POSIX sh (`#!/bin/sh`).
- Source shared helpers first.
- Keep `$ZSH` as the current repo-root alias used by scripts.

## Option Parsing Pattern

Use boolean flags plus a `case` parser.

```bash
UNINSTALL=false
INSTALL_CLAUDE_MD=true

while [ $# -gt 0 ]; do
    case $1 in
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done
```

## Symlink Install Pattern

```bash
rm -f ~/.claude/CLAUDE.md
ln -sf $ZSH/ai/CLAUDE.md ~/.claude/CLAUDE.md

mkdir -p ~/.claude/agents
for agent in $ZSH/ai/agents/*.*; do
    agent_name=$(basename "$agent")
    rm -f ~/.claude/agents/"$agent_name"
    ln -sf "$agent" ~/.claude/agents/"$agent_name"
done
```

Key points:

- Use `rm -f` then `ln -sf` for idempotent relinking.
- Use `mkdir -p` for target directories.
- Use `basename` for stable destination filenames.

## Uninstall Safety Pattern

```bash
if [ -L ~/.claude/CLAUDE.md ]; then
    rm -f ~/.claude/CLAUDE.md
elif [ -f ~/.claude/CLAUDE.md ]; then
    warning "~/.claude/CLAUDE.md is a regular file, not a symlink - skipping"
fi
```

Key points:

- Remove only symlinks.
- Warn and skip regular files.

## JSON Merge Pattern

Use `merge_json_settings` from `ai/helpers/json-settings.sh`.

```bash
if merge_json_settings "$SETTINGS_FILE" "$HOOKS_CONFIG" "hooks"; then
    success "Configured Claude Code hooks"
fi
```

Key points:

- Validate inputs before merge.
- Guard optional dependencies (`jq`) inside the helper.
- Merge through temp file and atomic move.

## Output Pattern

Use output helpers for all user-facing messages.

```bash
info "Installing Claude configuration..."
success "Symlinked agents"
warning "jq not found - settings merge skipped"
error "Settings file not found"
```

Key points:

- `error` goes to stderr.
- Keep success/warning/info/error semantics consistent.
