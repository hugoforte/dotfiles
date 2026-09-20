#!/bin/sh

# Sanity-check ~/.claude/settings.json: valid JSON, and a summary of what it contains.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$ZSH/ai/helpers/output.sh"
. "$ZSH/ai/helpers/settings-reconcile.sh"

SETTINGS_FILE="$HOME/.claude/settings.json"

# jq presence, file presence and JSON validity are the reconciliation
# module's precondition; ask it rather than repeating the checks here.
settings_file_ready "$SETTINGS_FILE" || exit 1
success "Settings file has valid JSON"

info "model:            $(jq -r '.model // "(unset)"' "$SETTINGS_FILE")"
info "enabled plugins:  $(jq -r '.enabledPlugins // {} | to_entries | map(select(.value)) | length' "$SETTINGS_FILE")"
info "allowed tools:    $(jq -r '.permissions.allow // [] | length' "$SETTINGS_FILE")"
info "denied tools:     $(jq -r '.permissions.deny // [] | length' "$SETTINGS_FILE")"
info "hook events:      $(jq -r '.hooks // {} | keys | join(", ") | if . == "" then "(none)" else . end' "$SETTINGS_FILE")"
