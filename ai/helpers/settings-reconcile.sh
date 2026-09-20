#!/bin/sh

# The settings reconciliation module: one spec for the keys this repo manages,
# and the three directions that move them between the repo fragment and a live
# settings file.
#
#   reconcile_settings merge  <target> <fragment>   fragment -> target
#   reconcile_settings check  <target> <fragment>   report drift, return 1 if any
#   reconcile_settings export <target> <fragment>   target -> fragment
#
# A managed key is a leaf path of the fragment - arrays count as leaves, objects
# do not. Nothing outside that set is read or written in any direction, so the
# live file keeps its machine-local keys and the fragment never acquires keys it
# did not already declare.
#
# Arrays union in both write directions and neither direction deletes, so an
# entry only leaves a file when a human removes it. `check` reports the two
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
'

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
    jq --slurpfile frag "$reconcile_fragment" "$SETTINGS_SPEC_JQ"'
        $frag[0] as $f
        | reduce ($f | managed_paths)[] as $p (.;
            setpath($p; reconciled(value_at(.; $p); ($f | getpath($p)))))
    ' "$reconcile_target" | settings_write_json "$reconcile_target"
}

reconcile_check() {
    reconcile_target="$1"; reconcile_fragment="$2"
    settings_file_ready "$reconcile_fragment" || return 1
    settings_file_ready "$reconcile_target" || return 1
    reconcile_report="$(jq -r --slurpfile frag "$reconcile_fragment" "$SETTINGS_SPEC_JQ"'
        . as $live | $frag[0] as $f
        | ($f | managed_paths)[] as $p
        | ($p | join(".")) as $name
        | ($f | getpath($p)) as $fv
        | value_at($live; $p) as $lv
        | if $lv == null then "MISSING \($name)"
          elif ($lv | type) != ($fv | type) then
              "DIFF \($name): live=\($lv | tojson) repo=\($fv | tojson)"
          elif ($fv | type) == "array" then
              (($fv - $lv) | if length > 0 then "MISSING \($name): \(join(", "))" else empty end),
              (($lv - $fv) | if length > 0 then "EXTRA \($name): \(join(", "))" else empty end)
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
    jq --slurpfile live "$reconcile_target" "$SETTINGS_SPEC_JQ"'
        $live[0] as $l
        | reduce (managed_paths)[] as $p (.;
            setpath($p; reconciled(getpath($p); value_at($l; $p))))
    ' "$reconcile_fragment" | settings_write_json "$reconcile_fragment"
}

# reconcile_settings <merge|check|export> <target> <fragment>
# Returns 0 when the direction succeeded and found nothing wrong, 1 otherwise.
reconcile_settings() {
    if [ $# -ne 3 ]; then
        error "Usage: reconcile_settings <merge|check|export> <target> <fragment>"
        return 1
    fi
    case "$1" in
        merge)  reconcile_merge "$2" "$3" ;;
        check)  reconcile_check "$2" "$3" ;;
        export) reconcile_export "$2" "$3" ;;
        *)      error "reconcile_settings: unknown direction '$1'"; return 1 ;;
    esac
}
