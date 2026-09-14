#!/bin/sh

# Sanity-check ~/.claude/settings.json: valid JSON, and a summary of what it contains.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$ZSH/ai/helpers/output.sh"

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    error "Settings file not found: $SETTINGS_FILE"
    exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
    error "jq not found - required for settings validation"
    exit 1
fi

if ! jq empty "$SETTINGS_FILE" > /dev/null 2>&1; then
    error "Settings file contains invalid JSON"
    exit 1
fi
success "Settings file has valid JSON"

info "model:            $(jq -r '.model // "(unset)"' "$SETTINGS_FILE")"
info "enabled plugins:  $(jq -r '.enabledPlugins // {} | to_entries | map(select(.value)) | length' "$SETTINGS_FILE")"
info "allowed tools:    $(jq -r '.permissions.allow // [] | length' "$SETTINGS_FILE")"
info "denied tools:     $(jq -r '.permissions.deny // [] | length' "$SETTINGS_FILE")"
info "hook events:      $(jq -r '.hooks // {} | keys | join(", ") | if . == "" then "(none)" else . end' "$SETTINGS_FILE")"
