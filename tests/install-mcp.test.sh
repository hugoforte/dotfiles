#!/bin/sh

# Fixture suite for the MCP servers in ai/install.sh: the servers the overlays declare in
# ai/claude/mcp.json are set in the user scope of every Claude config folder, ~/.claude's in
# ~/.claude.json and an extra folder's in its own .claude.json, by name, leaving the rest of the file
# and every server added by hand as they were. --check reports a server missing or changed.
#
# Two overlays, listed by a fixture ai/secrets/machine.local.psd1, and RIG_ROOT pointing at an empty
# directory so the real rig checkout stays out of it. HOME has a space in it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

command -v jq > /dev/null 2>&1 || { echo "install mcp: jq not found; skipped"; exit 0; }

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home dir"
cwd="$work/cwd"
first="$work/private/first"
second="$work/private/second"
extra="$home/.claude-extra"
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$home" "$cwd" "$first/ai/claude" "$second/ai/claude" "$extra"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '~/.claude-extra\n' > "$first/ai/claude/config-dirs"
printf '{ "mcpServers": { "search": { "type": "http", "url": "https://mcp.example.com" } } }\n' > "$first/ai/claude/mcp.json"
printf '{ "mcpServers": { "search": { "type": "http", "url": "https://elsewhere.example.com" }, "docs": { "type": "http", "url": "https://docs.example.com" } } }\n' > "$second/ai/claude/mcp.json"

# A signed-in folder, with a server added by hand: neither is this repo's.
printf '{ "userID": "kept", "mcpServers": { "mine": { "type": "stdio", "command": "mine" } } }\n' > "$home/.claude.json"

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n        '%s'\n    )\n}\n" "$(win "$first")" "$(win "$second")" > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

run()     { (cd "$cwd" && sh "$repo/ai/install.sh" --mcp-only "$@" 2>&1); }
says()    { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
server()  { jq -c ".mcpServers[\"$2\"]" "$1"; }

out="$(run)"; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "~/.claude.json gets the first overlay's server" '{"type":"http","url":"https://mcp.example.com"}' "$(server "$home/.claude.json" search)"
assert_eq "and a later overlay's other server" '{"type":"http","url":"https://docs.example.com"}' "$(server "$home/.claude.json" docs)"
assert_eq "and keeps the server added by hand" '{"type":"stdio","command":"mine"}' "$(server "$home/.claude.json" mine)"
assert_eq "and the rest of the file" "kept" "$(jq -r .userID "$home/.claude.json")"
assert_eq "an extra folder gets the servers in its own .claude.json" '{"type":"http","url":"https://mcp.example.com"}' "$(server "$extra/.claude.json" search)"
assert_eq "nothing is put inside ~/.claude" "n" "$(if [ -e "$home/.claude/.claude.json" ]; then echo y; else echo n; fi)"
assert_eq "install warns that a later overlay's clashing name is not set" "y" "$(says "$out" "MCP server search not set")"

printf '{ "mcpServers": { "docs": { "type": "http", "url": "https://docs" } } }\n' > "$second/ai/claude/mcp.json"
out="$(run --check)"; rc=$?
assert_eq "--check is clean once set" "0" "$rc"

jq '.mcpServers.search.url = "https://changed"' "$extra/.claude.json" > "$work/changed" && mv "$work/changed" "$extra/.claude.json"
out="$(run --check)"; rc=$?
assert_eq "--check fails on a server changed by hand" "1" "$rc"
assert_eq "--check names the file and the server" "y" "$(says "$out" ".claude-extra/.claude.json lacks or differs on MCP servers: search")"

rm "$extra/.claude.json"
out="$(run --check)"; rc=$?
assert_eq "--check fails on a folder with no .claude.json yet" "1" "$rc"
run > /dev/null
assert_eq "install creates it" '{"type":"http","url":"https://mcp.example.com"}' "$(server "$extra/.claude.json" search)"

# Modes mean nothing to Windows' ACLs, so these hold on a Mac or Linux only.
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *)
        mode() { ls -l "$1" | cut -c1-10; }
        assert_eq "a .claude.json install creates is private" "-rw-------" "$(mode "$extra/.claude.json")"
        chmod 600 "$home/.claude.json"
        jq 'del(.mcpServers.search)' "$home/.claude.json" > "$work/changed" && cat "$work/changed" > "$home/.claude.json"
        (umask 022; run > /dev/null)
        assert_eq "rewriting .claude.json keeps its mode" "-rw-------" "$(mode "$home/.claude.json")"
        ;;
esac

printf '{ "mcpServers": [] }\n' > "$second/ai/claude/mcp.json"
out="$(run --check)"; rc=$?
assert_eq "--check fails on an mcp.json that is not an object of servers" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" "second/ai/claude/mcp.json: mcpServers is not an object")"

assert_summary "install.sh MCP servers"
