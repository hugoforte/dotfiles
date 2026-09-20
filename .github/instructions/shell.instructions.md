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
. $ZSH/ai/helpers/settings-reconcile.sh
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

## Settings Reconciliation Pattern

Use `reconcile_settings` from `ai/helpers/settings-reconcile.sh`. The module owns the managed-key spec; the direction and both file paths are arguments.

```bash
if reconcile_settings merge "$SETTINGS_FILE" "$SETTINGS_FRAGMENT"; then
    success "Merged ai/claude/settings.json into $SETTINGS_FILE"
fi
```

Key points:

- Take the target path as a parameter; do not read a module-level constant.
- Return failure; do not signal through a global flag.
- Guard optional dependencies (`jq`) inside the helper.
- Write through a temp file and an atomic move.

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
