#!/bin/sh

# The settings reconciliation module: one spec for the keys this repo manages,
# and the three directions that move them between the repo fragment and a live
# settings file.
#
#   reconcile_settings merge  <target> <fragment> [bin]   fragment -> target
#   reconcile_settings check  <target> <fragment> [bin]   report drift, return 1 if any
#   reconcile_settings export <target> <fragment> [bin]   target -> fragment
#
# A hook of this repo's is a command hook, under a managed hooks array, whose
# first argument is a program in [bin] - named bare in the fragment, by its
# absolute path in a live file, so the hook is found whatever PATH the agent was
# started with. The fragment owns these hooks: merge replaces every one in the
# live file, whichever checkout's path it names, with the fragment's at [bin];
# check reports one the fragment does not hold as STALE drift; export never
# carries one back, so no machine path reaches the repo. A hook named in shell
# form by a bare [bin] program, as this repo once wrote them, counts as one too.
# Without [bin] no hook is this repo's, and hooks reconcile as written.
#
# A managed key is a leaf path of the fragment - arrays count as leaves, objects
# do not. Nothing outside that set is read or written in any direction, so the
# live file keeps its machine-local keys and the fragment never acquires keys it
# did not already declare.
#
# Arrays union in both write directions and neither direction deletes, so an
# entry only leaves a file when a human removes it - except a hook of ours,
# which merge replaces as described above. `check` reports the two
# asymmetries separately: repo entries absent from the live file are drift,
# live-only entries are informational (they are the accumulated "always allow"
# answers, kept with `merge`'s counterpart, `export`).
#
# Callers pass paths, so fixtures work without touching ~/.claude.

# The managed-key spec, as jq definitions shared by every direction.
SETTINGS_SPEC_JQ='
def managed_paths:
    [paths(type != "object") | select(all(.[]; type == "string"))];

def value_at($doc; $p):
    try ($doc | getpath($p)) catch null;

def reconciled($base; $incoming):
    if $incoming == null then $base
    elif ($base | type) == "array" and ($incoming | type) == "array" then
        ($base + $incoming) | unique
    else $incoming
    end;

def hook_paths:
    managed_paths | map(select(.[0] == "hooks"));

def names_program($programs):
    . as $s | any($programs[]; . as $n | $s == $n or ($s | endswith("/bin/" + $n)));

def ours($programs):
    type == "object" and .type == "command" and (.command | type) == "string"
    and (if (.args | type) == "array" then
             (.args[0] | type) == "string" and (.args[0] | names_program($programs))
         else
             .command as $c | any($programs[]; . == $c)
         end);

# Over an array of hook groups ({matcher, hooks: [...]}).
def group_hooks(f):
    map(if type == "object" and (.hooks | type) == "array" then .hooks |= f else . end);

def without_ours($programs):
    group_hooks(map(select(ours($programs) | not)))
    | map(select(type != "object" or (.hooks | type) != "array" or (.hooks | length) > 0));

def ours_in($programs):
    [.[]? | .hooks? | arrays | .[] | select(ours($programs))];

# The fragment with each of its hooks of ours pointed at $bin.
def absolute_fragment($bin; $programs):
    reduce hook_paths[] as $p (.;
        setpath($p; getpath($p) | group_hooks(map(
            if ours($programs) and (.args | type) == "array"
                and (.args[0] | contains("/") | not)
            then .args[0] = "\($bin)/\(.args[0])" else . end))));

# A document with every hook of ours taken out of the arrays at $paths.
def strip_ours($paths; $programs):
    reduce $paths[] as $p (.;
        if (value_at(.; $p) | type) == "array"
        then setpath($p; getpath($p) | without_ours($programs)) else . end);

def entry_text:
    if type == "string" then . else tojson end;
'

# settings_bin_programs <bin>: the names of the files in <bin>, as a JSON array.
settings_bin_programs() {
    for settings_program in "$1"/*; do
        [ -f "$settings_program" ] && basename "$settings_program"
    done | jq -R . | jq -sc .
}

# settings_file_ready <file>: jq installed, file present, contents valid JSON.
settings_file_ready() {
    if ! command -v jq > /dev/null 2>&1; then
        error "jq not found - install it (winget install jqlang.jq)"
        return 1
    fi
    if [ ! -f "$1" ]; then
        error "$1 missing"
        return 1
    fi
    if ! jq empty "$1" > /dev/null 2>&1; then
        error "$1 contains invalid JSON"
        return 1
    fi
    return 0
}

# settings_write_json <destination>: replace destination with the JSON on stdin.
# An empty stream means the jq upstream of it failed, so the destination is left
# alone rather than truncated. jq on Windows writes CRLF; .gitattributes wants LF
# everywhere, and jq escapes any carriage return inside a string, so strip them.
settings_write_json() {
    tr -d '\r' > "$1.tmp"
    if [ ! -s "$1.tmp" ] || ! jq empty "$1.tmp" > /dev/null 2>&1; then
        rm -f "$1.tmp"
        error "Refusing to write invalid JSON to $1"
        return 1
    fi
    mv "$1.tmp" "$1"
}

reconcile_merge() {
    reconcile_target="$1"; reconcile_fragment="$2"
    settings_file_ready "$reconcile_fragment" || return 1
    if [ ! -f "$reconcile_target" ]; then
        echo '{}' > "$reconcile_target"
        info "Created $reconcile_target"
    fi
    settings_file_ready "$reconcile_target" || return 1
    jq --slurpfile frag "$reconcile_fragment" --arg bin "$reconcile_bin" \
        --argjson programs "$reconcile_programs" "$SETTINGS_SPEC_JQ"'
        ($frag[0] | absolute_fragment($bin; $programs)) as $f
        | reduce ($f | managed_paths)[] as $p (strip_ours($f | hook_paths; $programs);
            setpath($p; reconciled(value_at(.; $p); ($f | getpath($p)))))
    ' "$reconcile_target" | settings_write_json "$reconcile_target"
}

reconcile_check() {
    reconcile_target="$1"; reconcile_fragment="$2"
    settings_file_ready "$reconcile_fragment" || return 1
    settings_file_ready "$reconcile_target" || return 1
    reconcile_report="$(jq -r --slurpfile frag "$reconcile_fragment" --arg bin "$reconcile_bin" \
        --argjson programs "$reconcile_programs" "$SETTINGS_SPEC_JQ"'
        . as $live | ($frag[0] | absolute_fragment($bin; $programs)) as $f
        | ($f | managed_paths)[] as $p
        | ($p | join(".")) as $name
        | ($f | getpath($p)) as $fv
        | value_at($live; $p) as $lv
        | if $lv == null then "MISSING \($name)"
          elif ($lv | type) != ($fv | type) then
              "DIFF \($name): live=\($lv | tojson) repo=\($fv | tojson)"
          elif ($fv | type) == "array" then
              (($fv - $lv) | if length > 0 then "MISSING \($name): \(map(entry_text) | join(", "))" else empty end),
              (($lv - $fv) | if length > 0 then "EXTRA \($name): \(map(entry_text) | join(", "))" else empty end),
              ((($lv | ours_in($programs)) - ($fv | ours_in($programs)))
                  | if length > 0 then "STALE \($name): \(map(entry_text) | join(", "))" else empty end)
          elif $lv != $fv then "DIFF \($name): live=\($lv) repo=\($fv)"
          else empty
          end
    ' "$reconcile_target")" || return 1
    if [ -z "$reconcile_report" ]; then
        success "$reconcile_target matches $reconcile_fragment"
        return 0
    fi
    printf '%s\n' "$reconcile_report" | while IFS= read -r reconcile_line; do
        case "$reconcile_line" in
            EXTRA*) info "$reconcile_line" ;;
            *)      warning "$reconcile_line" ;;
        esac
    done
    if printf '%s\n' "$reconcile_report" | grep -qv '^EXTRA'; then
        return 1
    fi
    return 0
}

reconcile_export() {
    reconcile_target="$1"; reconcile_fragment="$2"
    settings_file_ready "$reconcile_target" || return 1
    settings_file_ready "$reconcile_fragment" || return 1
    jq --slurpfile live "$reconcile_target" --argjson programs "$reconcile_programs" "$SETTINGS_SPEC_JQ"'
        hook_paths as $hp
        | ($live[0] | strip_ours($hp; $programs)) as $l
        | reduce (managed_paths)[] as $p (.;
            setpath($p; reconciled(getpath($p); value_at($l; $p))))
    ' "$reconcile_fragment" | settings_write_json "$reconcile_fragment"
}

# reconcile_settings <merge|check|export> <target> <fragment> [bin]
# Returns 0 when the direction succeeded and found nothing wrong, 1 otherwise.
reconcile_settings() {
    if [ $# -ne 3 ] && [ $# -ne 4 ]; then
        error "Usage: reconcile_settings <merge|check|export> <target> <fragment> [bin]"
        return 1
    fi
    reconcile_bin="${4:-}"
    reconcile_programs='[]'
    if [ -n "$reconcile_bin" ]; then
        reconcile_programs="$(settings_bin_programs "$reconcile_bin")" || return 1
    fi
    case "$1" in
        merge)  reconcile_merge "$2" "$3" ;;
        check)  reconcile_check "$2" "$3" ;;
        export) reconcile_export "$2" "$3" ;;
        *)      error "reconcile_settings: unknown direction '$1'"; return 1 ;;
    esac
}
