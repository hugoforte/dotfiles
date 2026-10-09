#!/bin/sh

# Claude Code substitutes a skill's arguments into its SKILL.md: `$ARGUMENTS`
# for all of them, and a bare `$1`, `$2`, … for each word. A shell helper in a
# skill that reads its own parameters as `$1` therefore runs with a word of
# the user's request in their place. hf-scryer's `gql` sent the query
# "Matter" because it was invoked about Dark Matter. `${1}` is left alone, so
# the helpers write that.
#
# Only the hf-* skills are ours; the rest of ai/skills is vendored.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

echo "hf-* skills read shell parameters as \${N}"

bare="$(grep -nE '\$[0-9]' "$REPO_ROOT"/ai/skills/hf-*/SKILL.md)"
assert_eq "no hf-* SKILL.md has a bare \$N for Claude Code to substitute" "" "$bare"

assert_summary "skill-positional-params"
