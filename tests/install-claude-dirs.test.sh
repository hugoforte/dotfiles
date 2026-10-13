#!/bin/sh

# Fixture suite for the extra Claude config folders in ai/install.sh: a folder an overlay names in
# its ai/claude/config-dirs gets exactly what ~/.claude gets (CLAUDE.md, agents, skills, the
# managed settings), checked the same way, and nothing else in it is touched.
#
# The overlay is the one a fixture ai/secrets/machine.local.psd1 lists, and RIG_ROOT points at an
# empty directory so the real rig checkout stays out of it. HOME has a space in it, as a Windows
# user name can, and install runs from an empty directory so a path that went astray shows up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home dir"
cwd="$work/cwd"
overlay="$work/private/personal"
extra="$home/.claude-extra"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/own" "$repo/ai/agents" "$repo/ai/claude" "$repo/ai/secrets" \
         "$home" "$cwd" "$overlay/ai/claude" "$extra"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"

# A folder already signed in and used: what Claude Code keeps there is not this repo's.
mkdir -p "$extra/projects/some-project"
printf '{ "token": "kept" }\n' > "$extra/.credentials.json"
printf '{ "userID": "kept" }\n' > "$extra/.claude.json"
printf '{ "theme": "dark" }\n' > "$extra/settings.json"
printf '{ "display": "kept" }\n' > "$extra/history.jsonl"
printf '{ "type": "kept" }\n' > "$extra/projects/some-project/session.jsonl"

# CRLF, a comment and a blank line, as an overlay edited on Windows would carry them.
printf '# extra Claude config folders\r\n\r\n~/.claude-extra\r\n' > "$overlay/ai/claude/config-dirs"

# machine.local.psd1 holds Windows paths on a real machine; install.sh converts them.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$overlay")" > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

run()       { (cd "$cwd" && sh "$repo/ai/install.sh" "$@" --no-rig-skills --no-overlay-skills --no-bruno 2>&1); }
install()   { run > /dev/null; }
check()     { run --check; }
is_link()   { if [ -L "$1" ]; then echo y; else echo n; fi; }
exists()    { if [ -e "$1" ] || [ -L "$1" ]; then echo y; else echo n; fi; }
says()      { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
config()    { printf "$1" > "$overlay/ai/claude/config-dirs"; }
# fresh_home: an empty home and an empty working directory, for a scenario of its own
fresh_home() { rm -rf "$home" "$cwd"; mkdir -p "$home" "$cwd"; }

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
assert_eq "its history is left alone" '{ "display": "kept" }' "$(cat "$extra/history.jsonl")"
assert_eq "its projects are left alone" '{ "type": "kept" }' "$(cat "$extra/projects/some-project/session.jsonl")"
assert_eq "a space in HOME does not split it: nothing beside it" "n" "$(exists "$work/home")"
assert_eq "and nothing in the working directory" "" "$(ls -A "$cwd")"

out="$(check)"; rc=$?
assert_eq "--check is clean with both folders in place" "0" "$rc"

rm "$extra/agents/helper.md"
out="$(check)"; rc=$?
assert_eq "--check fails on a link missing from the extra folder" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" ".claude-extra/agents/helper.md missing")"

# A folder named but never created is made on install, ready for its login.
printf '~/.claude-new\n' >> "$overlay/ai/claude/config-dirs"
install
assert_eq "install creates a named folder that did not exist" "y" "$(is_link "$home/.claude-new/CLAUDE.md")"

# The overlay stops naming a folder: install leaves it as it was, and --check no longer asks.
config '~/.claude-extra\n'
install
out="$(check)"; rc=$?
assert_eq "--check ignores a folder no overlay names any more" "0" "$rc"

# --uninstall takes this repo's links out of a route folder and leaves its login.
run --uninstall > /dev/null
assert_eq "--uninstall removes a route folder's CLAUDE.md link" "n" "$(exists "$extra/CLAUDE.md")"
assert_eq "--uninstall removes a route folder's agent links" "n" "$(exists "$extra/agents/helper.md")"
assert_eq "--uninstall removes a route folder's skill links" "n" "$(exists "$extra/skills/own")"
assert_eq "--uninstall keeps a route folder's login" '{ "token": "kept" }' "$(cat "$extra/.credentials.json")"

rm "$overlay/ai/claude/config-dirs"
install; rc=$?
assert_eq "install succeeds when no overlay names a folder" "0" "$rc"
out="$(check)"; rc=$?
assert_eq "and --check is clean with ~/.claude alone" "0" "$rc"

# A route folder with a space in its name is one folder.
fresh_home
config '~/Claude Client\n'
install
assert_eq "a route folder with a space gets CLAUDE.md" "y" "$(is_link "$home/Claude Client/CLAUDE.md")"
assert_eq "and is not split at the space" "n" "$(exists "$home/Claude")"
out="$(check)"; rc=$?
assert_eq "and --check is clean with it in place" "0" "$rc"

# The last line counts without a newline after it.
fresh_home
config '~/.claude-last'
install
assert_eq "a last line without a newline is a folder" "y" "$(is_link "$home/.claude-last/CLAUDE.md")"

# Comments may be indented or follow a path; a path may start ~\ as Windows writes it.
fresh_home
config '  # route folders\n~/.claude-x   # client work\n~\\.claude-win\n'
out="$(run)"
assert_eq "a trailing comment is not part of the path" "y" "$(is_link "$home/.claude-x/CLAUDE.md")"
assert_eq "~\\ is the home directory" "y" "$(is_link "$home/.claude-win/CLAUDE.md")"
assert_eq "an indented comment is not a path" "n" "$(says "$out" "route folders")"
out="$(check)"; rc=$?
assert_eq "and --check is clean with them in place" "0" "$rc"

# A path that is not absolute would land wherever install happened to run: refuse it.
fresh_home
config '.claude-rel\n'
out="$(run)"; rc=$?
assert_eq "install carries on past a relative path" "0" "$rc"
assert_eq "install warns about it" "y" "$(says "$out" ".claude-rel is not an absolute path")"
assert_eq "and creates nothing for it" "" "$(ls -A "$cwd")"
out="$(check)"; rc=$?
assert_eq "--check fails on a relative path" "1" "$rc"

# A folder named twice, or naming ~/.claude itself, is set up once: one settings backup, of the
# file as it was.
fresh_home
mkdir -p "$home/.claude"
printf '{ "model": "opus" }\n' > "$home/.claude/settings.json"
config '~/.claude\n~/.claude/\n'
install
set -- "$home/.claude"/settings.json.backup.*
assert_eq "~/.claude named again gets one settings backup" "1" "$#"
assert_eq "and it holds the settings as they were" '{ "model": "opus" }' "$(cat "$1")"

assert_summary "install.sh extra Claude config folders"
