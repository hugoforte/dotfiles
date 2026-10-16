#!/bin/sh

# Fixture suite for the hook commands ai/install.sh writes into settings.json: a hook naming a
# program in bin/ is written as that program's absolute path, so it runs with a PATH that lacks
# bin/, as an app started from the Dock has; and --check fails when such a hook does not run.
#
# HOME has a space in it, as a Windows user name can, and so does the checkout, so a path left
# unquoted in the command shows up.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

if ! command -v jq > /dev/null 2>&1; then
    printf '  SKIP  jq not found; install.sh merges no settings without it\n'
    assert_summary "install-hooks"
    exit $?
fi

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo dir"
home="$work/home dir"
mkdir -p "$repo/ai/helpers" "$repo/ai/claude" "$repo/ai/secrets" "$repo/bin" "$home"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
cp "$REPO_ROOT/bin/agent-guard" "$REPO_ROOT/bin/agent-guard.mjs" "$repo/bin/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
cp "$REPO_ROOT/ai/claude/settings.json" "$repo/ai/claude/settings.json"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

run() { sh "$repo/ai/install.sh" "$@" --settings-only 2>&1; }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
hook_command() {
    jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash|PowerShell") | .hooks[].command' \
        "$home/.claude/settings.json"
}

run > /dev/null
command="$(hook_command)"

printf '=== the merged hook names its program by absolute path ===\n'
assert_eq "one guard hook in the live file" "1" "$(printf '%s\n' "$command" | wc -l | tr -d ' ')"
case "$command" in
    \"/*/bin/agent-guard\"|\"[A-Za-z]:/*/bin/agent-guard\") absolute=y ;;
    *)                                                      absolute=n ;;
esac
assert_eq "quoted absolute path to bin/agent-guard: $command" "y" "$absolute"

printf '=== it runs with a PATH that lacks bin/ ===\n'
node_dir="$(dirname "$(command -v node)")"
decision="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1"}}' \
    | PATH="$node_dir:/usr/bin:/bin" sh -c "$command" \
    | jq -r .hookSpecificOutput.permissionDecision 2>/dev/null)"
assert_eq "asks before a merge" "ask" "$decision"

printf '=== --check passes, and fails once the hook stops running ===\n'
out="$(run --check)"; rc=$?
printf '%s\n' "$out" | sed 's/^/        /'
assert_eq "check passes on the merged file" "0" "$rc"
assert_eq "and says the hook runs" "y" "$(says "$out" "hook runs")"

printf '#!/bin/sh\nexit 127\n' > "$repo/bin/agent-guard"
out="$(run --check)"; rc=$?
printf '%s\n' "$out" | sed 's/^/        /'
assert_eq "check fails on a hook that does not run" "1" "$rc"
assert_eq "and names it" "y" "$(says "$out" "hook does not run")"

printf '=== a second install keeps one entry ===\n'
cp "$REPO_ROOT/bin/agent-guard" "$repo/bin/agent-guard"
run > /dev/null
assert_eq "still one guard hook" "1" "$(hook_command | wc -l | tr -d ' ')"

printf '\n'
assert_summary "install-hooks"
