#!/bin/sh

# Fixture suite for the extra Claude config folders in ai/install.sh: a folder an overlay names in
# its ai/claude/config-dirs gets exactly what ~/.claude gets (CLAUDE.md, agents, skills, the
# managed settings), checked the same way, and nothing else in it is touched.
#
# The overlay is the one a fixture ai/secrets/machine.local.psd1 lists, and RIG_ROOT points at an
# empty directory so the real rig checkout stays out of it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home"
overlay="$work/private/personal"
extra="$home/.claude-extra"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/own" "$repo/ai/agents" "$repo/ai/claude" "$repo/ai/secrets" \
         "$home" "$overlay/ai/claude" "$extra"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"

# A folder already signed in: what Claude Code keeps there is not this repo's.
printf '{ "token": "kept" }\n' > "$extra/.credentials.json"
printf '{ "userID": "kept" }\n' > "$extra/.claude.json"
printf '{ "theme": "dark" }\n' > "$extra/settings.json"

# CRLF, a comment and a blank line, as an overlay edited on Windows would carry them.
printf '# extra Claude config folders\r\n\r\n~/.claude-extra\r\n' > "$overlay/ai/claude/config-dirs"

# machine.local.psd1 holds Windows paths on a real machine; install.sh converts them.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$overlay")" > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

install() { sh "$repo/ai/install.sh" --no-rig-skills --no-overlay-skills --no-bruno > /dev/null 2>&1; }
check()   { sh "$repo/ai/install.sh" --check --no-rig-skills --no-overlay-skills --no-bruno 2>&1; }
is_link() { if [ -L "$1" ]; then echo y; else echo n; fi; }

install; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "~/.claude still gets CLAUDE.md" "y" "$(is_link "$home/.claude/CLAUDE.md")"
assert_eq "the extra folder gets CLAUDE.md" "$repo/ai/CLAUDE.md" "$(readlink "$extra/CLAUDE.md")"
assert_eq "the extra folder gets the agents" "y" "$(is_link "$extra/agents/helper.md")"
assert_eq "the extra folder gets the skills" "$repo/ai/skills/own" "$(readlink "$extra/skills/own")"
if command -v jq > /dev/null 2>&1; then
    assert_eq "the extra folder gets the managed settings" "sonnet" "$(jq -r .model "$extra/settings.json")"
    assert_eq "and keeps its own" "dark" "$(jq -r .theme "$extra/settings.json")"
fi
assert_eq "its login is left alone" '{ "token": "kept" }' "$(cat "$extra/.credentials.json")"
assert_eq "its .claude.json is left alone" '{ "userID": "kept" }' "$(cat "$extra/.claude.json")"

out="$(check)"; rc=$?
assert_eq "--check is clean with both folders in place" "0" "$rc"

rm "$extra/agents/helper.md"
out="$(check)"; rc=$?
assert_eq "--check fails on a link missing from the extra folder" "1" "$rc"
case "$out" in *".claude-extra/agents/helper.md missing"*) named=y ;; *) named=n ;; esac
assert_eq "--check names it" "y" "$named"

# A folder named but never created is made on install, ready for its login.
printf '~/.claude-new\n' >> "$overlay/ai/claude/config-dirs"
install
assert_eq "install creates a named folder that did not exist" "y" "$(is_link "$home/.claude-new/CLAUDE.md")"

# The overlay stops naming a folder: install leaves it as it was, and --check no longer asks.
printf '~/.claude-extra\n' > "$overlay/ai/claude/config-dirs"
install
out="$(check)"; rc=$?
assert_eq "--check ignores a folder no overlay names any more" "0" "$rc"

rm "$overlay/ai/claude/config-dirs"
install; rc=$?
assert_eq "install succeeds when no overlay names a folder" "0" "$rc"
out="$(check)"; rc=$?
assert_eq "and --check is clean with ~/.claude alone" "0" "$rc"

assert_summary "install.sh extra Claude config folders"
