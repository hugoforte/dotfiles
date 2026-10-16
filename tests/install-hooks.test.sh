#!/bin/sh

# Fixture suite for the hooks ai/install.sh writes into settings.json: the guard is written in
# exec form with the checkout's absolute path to bin/agent-guard.mjs, so it runs with a PATH
# that lacks bin/, as an app started from the Dock has; and --check fails when such a hook does
# not run, or points at another checkout.
#
# HOME has a space in it, as a Windows user name can, and so does the checkout.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

for tool in jq node; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf '  SKIP  %s not found; this suite needs it\n' "$tool"
        assert_summary "install-hooks"
        exit $?
    fi
done

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo dir"
home="$work/home dir"
mkdir -p "$repo/ai/helpers" "$repo/ai/claude" "$repo/ai/secrets" "$repo/bin" "$home"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
cp "$REPO_ROOT/bin/agent-guard.mjs" "$repo/bin/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
cp "$REPO_ROOT/ai/claude/settings.json" "$repo/ai/claude/settings.json"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT
live="$home/.claude/settings.json"

run() { sh "$repo/ai/install.sh" "$@" --settings-only 2>&1; }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
guard_hooks() { jq -c '[.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[]]' "$live"; }

run > /dev/null
hook="$(guard_hooks)"

printf '=== the merged guard is exec form, pointing at this checkout ===\n'
assert_eq "one guard hook in the live file" "1" "$(printf '%s' "$hook" | jq length)"
script="$(printf '%s' "$hook" | jq -r '.[0].args[0]')"
case "$script" in
    /*/bin/agent-guard.mjs|[A-Za-z]:/*/bin/agent-guard.mjs) absolute=y ;;
    *)                                                      absolute=n ;;
esac
assert_eq "absolute path to bin/agent-guard.mjs: $script" "y" "$absolute"
assert_eq "it blocks the call when it cannot run" "block" "$(printf '%s' "$hook" | jq -r '.[0].onFailure')"

printf '=== it runs with a PATH that lacks bin/ ===\n'
node_dir="$(dirname "$(command -v node)")"
decision="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
    | PATH="$node_dir:/usr/bin:/bin" node "$script" \
    | jq -r .hookSpecificOutput.permissionDecision 2>/dev/null)"
assert_eq "asks before a merge" "ask" "$decision"

printf '=== --check passes, and fails once the hook stops running ===\n'
out="$(run --check)"; rc=$?
printf '%s\n' "$out" | sed 's/^/        /'
assert_eq "check passes on the merged file" "0" "$rc"
assert_eq "and says the hook runs" "y" "$(says "$out" "hook runs")"

cp "$repo/bin/agent-guard.mjs" "$work/agent-guard.mjs"
printf 'process.exit(1);\n' > "$repo/bin/agent-guard.mjs"
out="$(run --check)"; rc=$?
printf '%s\n' "$out" | sed 's/^/        /'
assert_eq "check fails on a hook that exits 1" "1" "$rc"
assert_eq "and names it" "y" "$(says "$out" "hook does not run")"
cp "$work/agent-guard.mjs" "$repo/bin/agent-guard.mjs"

printf '=== a hook another checkout wrote is drift, and is replaced by install ===\n'
jq '.hooks.PreToolUse += [{"matcher":"Bash|PowerShell","hooks":[{"type":"command","command":"node","args":["/gone/checkout/bin/agent-guard.mjs"],"onFailure":"block"}]}]' \
    "$live" > "$live.tmp" && mv "$live.tmp" "$live"
out="$(run --check)"; rc=$?
printf '%s\n' "$out" | sed 's/^/        /'
assert_eq "check fails" "1" "$rc"
assert_eq "names it STALE" "y" "$(says "$out" "STALE hooks.PreToolUse")"
assert_eq "and says it does not run" "y" "$(says "$out" "hook does not run: 'node' '/gone/checkout")"
run > /dev/null
assert_eq "install leaves one guard hook" "1" "$(guard_hooks | jq length)"
assert_eq "this checkout's" "$script" "$(guard_hooks | jq -r '.[0].args[0]')"

printf '\n'
assert_summary "install-hooks"
