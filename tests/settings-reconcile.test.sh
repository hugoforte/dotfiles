#!/bin/sh

# Fixture suite for ai/helpers/settings-reconcile.sh.
#
# reconcile_settings takes both paths as arguments, so every case here runs
# against files in a temp directory this script creates and removes. Nothing
# reads or writes ~/.claude.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"
. "$REPO_ROOT/ai/helpers/output.sh"
. "$REPO_ROOT/ai/helpers/settings-reconcile.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

# setup <fragment json> [live json]: start each case from a clean pair of
# files. An empty live argument leaves the target absent.
setup() {
    rm -rf "$work"
    mkdir -p "$work"
    printf '%s' "$1" | jq . > "$work/fragment.json"
    if [ -n "$2" ]; then
        printf '%s' "$2" | jq . > "$work/live.json"
    fi
}

# show <text>: echo a captured report indented, so a red run explains itself.
show() {
    printf '%s\n' "$1" | sed 's/^/        /'
}

printf '=== 1. repo-declared array entry missing from live must fail --check ===\n'
setup '{"permissions":{"allow":["Read","Grep","Glob"]}}' '{"permissions":{"allow":["Read","Grep"]}}'
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "exit 1 on missing array entry" "1" "$rc"
case "$out" in
    *"MISSING permissions.allow: Glob"*) named=y ;;
    *)                                   named=n ;;
esac
assert_eq "names the missing entry" "y" "$named"

printf '=== 2. live-only array extra stays informational (exit 0) ===\n'
setup '{"permissions":{"allow":["Read"]}}' '{"permissions":{"allow":["Read","Bash(ls:*)"]}}'
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "exit 0 on live-only extra" "0" "$rc"

printf '=== 3. missing AND extra at once: fails, reports both ===\n'
setup '{"permissions":{"allow":["Read","Glob"]}}' '{"permissions":{"allow":["Read","Bash(ls:*)"]}}'
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "exit 1" "1" "$rc"
case "$out" in *MISSING*) m=y ;; *) m=n ;; esac
case "$out" in *EXTRA*)   e=y ;; *) e=n ;; esac
assert_eq "reports MISSING and EXTRA" "yy" "$m$e"

printf '=== 4. scalar drift (e.g. model changed live) -> DIFF, exit 1 ===\n'
setup '{"model":"sonnet"}' '{"model":"opus"}'
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "exit 1 on scalar DIFF" "1" "$rc"

printf '=== 5. export: unmanaged live keys must not reach the fragment ===\n'
setup '{"permissions":{"allow":["Read"]}}' '{"permissions":{"allow":["Read","Bash(ls:*)"],"deny":["Bash(rm:*)"],"ask":["WebFetch"]},"secretToken":"hunter2"}'
reconcile_settings export "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
show "fragment after export: $(jq -c . "$work/fragment.json")"
assert_eq "permissions.deny NOT exported" "null" "$(jq -c '.permissions.deny' "$work/fragment.json")"
assert_eq "permissions.ask NOT exported"  "null" "$(jq -c '.permissions.ask' "$work/fragment.json")"
assert_eq "top-level secret NOT exported" "null" "$(jq -c '.secretToken' "$work/fragment.json")"
assert_eq "managed array unioned"         '["Bash(ls:*)","Read"]' "$(jq -c '.permissions.allow' "$work/fragment.json")"

printf '=== 6. merge: fragment scalars win, arrays union, unmanaged live keys survive ===\n'
setup '{"model":"sonnet","permissions":{"allow":["Read"]}}' '{"model":"opus","permissions":{"allow":["Bash(ls:*)"],"deny":["Bash(rm:*)"]},"machineLocal":{"token":"keepme"}}'
reconcile_settings merge "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
show "live after merge: $(jq -c . "$work/live.json")"
assert_eq "fragment scalar wins"      '"sonnet"' "$(jq -c '.model' "$work/live.json")"
assert_eq "arrays unioned"            '["Bash(ls:*)","Read"]' "$(jq -c '.permissions.allow' "$work/live.json")"
assert_eq "unmanaged nested key kept" '["Bash(rm:*)"]' "$(jq -c '.permissions.deny' "$work/live.json")"
assert_eq "unmanaged top-level kept"  '{"token":"keepme"}' "$(jq -c '.machineLocal' "$work/live.json")"

printf '=== 7. round trip closes: merge then export then check is clean ===\n'
setup '{"model":"sonnet","permissions":{"allow":["Read","Glob"]}}' '{"permissions":{"allow":["Bash(ls:*)"],"deny":["x"]}}'
reconcile_settings merge "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
reconcile_settings export "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "merge+export then check is clean" "0" "$rc"

printf '=== 8. merge creates a missing target rather than failing ===\n'
setup '{"model":"sonnet"}' ''
rm -f "$work/live.json"
reconcile_settings merge "$work/live.json" "$work/fragment.json" > /dev/null 2>&1; rc=$?
assert_eq "merge into absent target succeeds" "0" "$rc"
assert_eq "created file has the fragment"     '"sonnet"' "$(jq -c '.model' "$work/live.json" 2>/dev/null)"

printf '=== 9. invalid JSON is refused, original left intact ===\n'
setup '{"model":"sonnet"}' ''
printf '{not json' > "$work/live.json"
before="$(cat "$work/live.json")"
out="$(reconcile_settings merge "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "invalid target refused" "1" "$rc"
assert_eq "target left untouched"  "$before" "$(cat "$work/live.json")"
assert_eq "no .tmp left behind"    "" "$(ls "$work"/*.tmp 2>/dev/null)"

printf '=== 10. bad direction and bad arity are rejected ===\n'
setup '{"a":1}' '{"a":1}'
reconcile_settings bogus "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
assert_eq "unknown direction -> 1" "1" "$?"
reconcile_settings check "$work/live.json" > /dev/null 2>&1
assert_eq "wrong arity -> 1" "1" "$?"

printf '=== 11. no CR bytes written, whatever jq does on Windows ===\n'
setup '{"permissions":{"allow":["Read"]}}' '{"permissions":{"allow":["Bash(ls:*)"]}}'
reconcile_settings merge "$work/live.json" "$work/fragment.json" > /dev/null 2>&1
crcount="$(tr -dc '\r' < "$work/live.json" | wc -c | tr -d ' ')"
assert_eq "zero CR bytes in merged output" "0" "$crcount"

printf '=== 12. deep nesting and an object-valued array element ===\n'
setup '{"hooks":{"Stop":[{"matcher":"x"}]},"a":{"b":{"c":"deep"}}}' '{"a":{"b":{"c":"changed"}}}'
out="$(reconcile_settings check "$work/live.json" "$work/fragment.json" 2>&1)"; rc=$?
show "$out"
assert_eq "nested scalar drift detected" "1" "$rc"
case "$out" in *"a.b.c"*) dotted=y ;; *) dotted=n ;; esac
assert_eq "reports dotted nested path" "y" "$dotted"

printf '\n'
assert_summary "settings-reconcile"
