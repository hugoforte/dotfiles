#!/bin/sh

# Installs the AI tooling in this repo into the agents' home directories by symlink.
# Components: CLAUDE.md, agents, skills, settings. See --help.

# Derive repo root from script location (works regardless of where repo is cloned)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
. "$ZSH/ai/helpers/output.sh"
. "$ZSH/ai/helpers/settings-reconcile.sh"

# On Git Bash (MSYS), `ln -s` silently copies unless native symlinks are enabled.
# Native symlinks need Windows Developer Mode or an elevated shell.
case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS="winsymlinks:nativestrict" ;;
esac

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SETTINGS_FRAGMENT="$ZSH/ai/claude/settings.json"

# Skill directories: every ai/skills/<name>/ is linked into each of these.
# ~/.claude/skills is always used; the others only when their tool directory exists.
SKILL_TARGETS="$HOME/.claude/skills $HOME/.codex/skills $HOME/.copilot/skills"

skill_target_dirs() {
    for target in $SKILL_TARGETS; do
        parent="$(dirname "$target")"
        if [ "$target" = "$HOME/.claude/skills" ] || [ -d "$parent" ]; then
            echo "$target"
        fi
    done
}

# ---------------------------------------------------------------------------
# Link primitives
# ---------------------------------------------------------------------------

# link <src> <dst>: point dst at src, backing up whatever real file was already there.
#
# A symlink at dst holds no content of its own, so it is replaced without a backup. A real file
# is someone's work: it is moved aside, never deleted, under the same <leaf>.backup.<timestamp>
# name powershell/managed-link.ps1 uses, so one convention shows up in both languages.
link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        backup="$dst.backup.$(date +%Y%m%d_%H%M%S)"
        if ! mv "$dst" "$backup"; then
            error "Could not move $dst aside to $backup - leaving it alone"
            return 1
        fi
        warning "$dst was not a symlink - backed it up to $backup"
    fi
    ln -s "$src" "$dst"
}

# unlink_if_link <dst>: remove only if it is a symlink
unlink_if_link() {
    if [ -L "$1" ]; then
        rm -f "$1"
    fi
}

CHECK_FAILED=0

# check_link <src> <dst>: report the state of one managed link
check_link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        actual="$(readlink "$dst")"
        if [ "$actual" = "$src" ]; then
            success "$dst"
        else
            warning "$dst -> $actual (expected $src)"
            CHECK_FAILED=1
        fi
    elif [ -e "$dst" ]; then
        warning "$dst is a regular file or directory, not a symlink"
        CHECK_FAILED=1
    else
        warning "$dst missing"
        CHECK_FAILED=1
    fi
}

# ---------------------------------------------------------------------------
# Components: each has install_<c>, uninstall_<c>, check_<c>
# ---------------------------------------------------------------------------

install_claude_md() {
    mkdir -p "$CLAUDE_DIR"
    link "$ZSH/ai/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" && success "Linked CLAUDE.md"
}
uninstall_claude_md() {
    unlink_if_link "$CLAUDE_DIR/CLAUDE.md" && success "Removed CLAUDE.md link"
}
check_claude_md() {
    check_link "$ZSH/ai/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
}

install_agents() {
    mkdir -p "$CLAUDE_DIR/agents"
    for agent in "$ZSH"/ai/agents/*.md; do
        link "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
    success "Linked agents into $CLAUDE_DIR/agents"
}
uninstall_agents() {
    for agent in "$ZSH"/ai/agents/*.md; do
        unlink_if_link "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
    success "Removed agent links"
}
check_agents() {
    for agent in "$ZSH"/ai/agents/*.md; do
        check_link "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
}

install_skills() {
    for target in $(skill_target_dirs); do
        mkdir -p "$target"
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            link "$skill" "$target/$(basename "$skill")"
        done
        success "Linked skills into $target"
    done
}
uninstall_skills() {
    for target in $(skill_target_dirs); do
        [ -d "$target" ] || continue
        for skill in "$ZSH"/ai/skills/*/; do
            unlink_if_link "$target/$(basename "$skill")"
        done
    done
    success "Removed skill links"
}
check_skills() {
    for target in $(skill_target_dirs); do
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            check_link "$skill" "$target/$(basename "$skill")"
        done
    done
}

# Settings are merged, not linked: ~/.claude/settings.json also holds machine-local state.
install_settings() {
    mkdir -p "$CLAUDE_DIR"
    if [ -f "$SETTINGS_FILE" ]; then
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    if reconcile_settings merge "$SETTINGS_FILE" "$SETTINGS_FRAGMENT"; then
        success "Merged ai/claude/settings.json into $SETTINGS_FILE"
    fi
}
uninstall_settings() {
    info "Settings are merged, not linked; nothing to remove from $SETTINGS_FILE"
}
check_settings() {
    reconcile_settings check "$SETTINGS_FILE" "$SETTINGS_FRAGMENT" || CHECK_FAILED=1
}

# Copy the managed keys from the live file back into the repo fragment.
export_settings() {
    reconcile_settings export "$SETTINGS_FILE" "$SETTINGS_FRAGMENT" || exit 1
    success "Wrote managed keys from $SETTINGS_FILE to ai/claude/settings.json (review with git diff)"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

MODE=install
INSTALL_CLAUDE_MD=true
INSTALL_AGENTS=true
INSTALL_SKILLS=true
INSTALL_SETTINGS=true

disable_all() {
    INSTALL_CLAUDE_MD=false
    INSTALL_AGENTS=false
    INSTALL_SKILLS=false
    INSTALL_SETTINGS=false
}

show_help() {
    echo "Usage: $0 [MODE] [COMPONENT FLAGS]"
    echo ""
    echo "Symlinks CLAUDE.md, agents and skills from this repo into ~/.claude (and skills"
    echo "into ~/.codex and ~/.copilot when present), and merges ai/claude/settings.json"
    echo "into ~/.claude/settings.json."
    echo ""
    echo "Modes:"
    echo "  (default)           Install"
    echo "  --check             Report link drift without changing anything (exit 1 on drift)"
    echo "  --uninstall         Remove the symlinks"
    echo "  --settings-export   Copy the managed settings keys from ~/.claude/settings.json back into the repo"
    echo ""
    echo "Component flags:"
    echo "  --claude-md-only    Only CLAUDE.md"
    echo "  --agents-only       Only agent files"
    echo "  --skills-only       Only skills"
    echo "  --settings-only     Only settings merge"
    echo "  --no-claude-md      Skip CLAUDE.md"
    echo "  --no-agents         Skip agents"
    echo "  --no-skills         Skip skills"
    echo "  --no-settings       Skip settings merge"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Needs: Windows Developer Mode or an elevated shell for symlinks; jq for settings."
}

while [ $# -gt 0 ]; do
    case $1 in
        --uninstall)        MODE=uninstall ;;
        --check)            MODE=check ;;
        --settings-export)  MODE=export; disable_all; INSTALL_SETTINGS=true ;;
        --claude-md-only)   disable_all; INSTALL_CLAUDE_MD=true ;;
        --agents-only)      disable_all; INSTALL_AGENTS=true ;;
        --skills-only)      disable_all; INSTALL_SKILLS=true ;;
        --settings-only)    disable_all; INSTALL_SETTINGS=true ;;
        --no-claude-md)     INSTALL_CLAUDE_MD=false ;;
        --no-agents)        INSTALL_AGENTS=false ;;
        --no-skills)        INSTALL_SKILLS=false ;;
        --no-settings)      INSTALL_SETTINGS=false ;;
        -h|--help)          show_help; exit 0 ;;
        *)                  echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

if [ "$MODE" = "install" ] && [ "$INSTALL_SETTINGS" = "true" ] && ! command -v jq > /dev/null 2>&1; then
    warning "jq not found - settings merge will be skipped (winget install jqlang.jq)"
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

case $MODE in
    install)   info "Installing AI tooling from $ZSH…" ;;
    uninstall) info "Removing AI tooling links…" ;;
    check)     info "Checking AI tooling links…" ;;
    export)    info "Exporting settings…" ;;
esac

[ "$INSTALL_CLAUDE_MD" = "true" ] && ${MODE}_claude_md
[ "$INSTALL_AGENTS" = "true" ]    && ${MODE}_agents
[ "$INSTALL_SKILLS" = "true" ]    && ${MODE}_skills
[ "$INSTALL_SETTINGS" = "true" ]  && ${MODE}_settings

# Secrets under ai/secrets/ must never be committed in plaintext; verify on every check.
if [ "$MODE" = "check" ]; then
    if sh "$ZSH/ai/secrets/check-encrypted.sh"; then
        success "ai/secrets: all files encrypted"
    else
        CHECK_FAILED=1
    fi
fi

echo ""
case $MODE in
    install)   success "Done" ;;
    uninstall) success "Done" ;;
    export)    success "Done" ;;
    check)
        if [ "$CHECK_FAILED" = "1" ]; then
            warning "Drift found - run $0 to fix"
            exit 1
        fi
        success "Everything in place"
        ;;
esac
