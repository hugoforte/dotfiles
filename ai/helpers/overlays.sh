#!/bin/sh

# The overlay table in sh: which overlays a machine lists, where each path an overlay may ship
# comes from, and the skill registries they merge. Sourced by ai/install.sh and macos/. Its
# PowerShell twin is powershell/overlays.ps1; the two agree on the rules, not the code
# (docs/adr/0007-a-parallel-macos-entry-point.md), and tests/overlays-parity.test.sh holds them to it.
#
#   overlays_load <repo> [overlay...]  read the list; sets OVERLAYS, OVERLAY_KEY, OVERLAY_REPOS
#   overlay_sources <path>             the sources of a path in OVERLAY_TABLE
#   overlay_entries <pattern> [claimant...]  the entries an entries row in OVERLAY_TABLE matches
#   merged_skill_registry              every skill the registries list
#
# POSIX sh has no local, so every name these functions use is prefixed _ov.

# What an overlay may ship, one row per path: the path relative to a root, how many sources it may
# have, and the roots it is read from. README's "Private configuration: overlays" says what each is.
#   one      at most one source; two is an error naming both
#   all      every source, in order
#   entries  a pattern in one folder (*/ its folders, *.md its .md files) whose matches are linked by
#            name; the first to ship a name keeps it
#   overlays the listed overlays, in order; repo+overlays puts the repo first
# {KEY} in a path is the machine key, and with no key the path matches nothing. A path ending in /
# is a folder; every other is a file.
OVERLAY_TABLE='aws/config all repo+overlays
ssh/authorized_keys one overlays
machines/{KEY}.psd1 one overlays
machines/{KEY}.Brewfile one overlays
git/gitconfig all overlays
macos/Brewfile all overlays
macos/bootstrap.sh all overlays
ai/claude/config-dirs all overlays
machines/{KEY}.config-dirs all overlays
machines/ all overlays
powershell/tools.psd1 all repo+overlays
ai/secrets/registry.psd1 all repo+overlays
leak-check/terms.txt all overlays
ai/skills/*/ entries overlays
bruno/*/ entries overlays
ai/rules/*.md entries overlays
ai/agents/*.md entries overlays'

# The field separator of a merged_skill_registry line: ASCII unit separator. Not a tab: read
# collapses runs of a whitespace IFS, which would shift a shipped skill's empty Marker out of place.
REGISTRY_FS="$(printf '\037')"

# psd1_paths <machine.local.psd1> <key>: the paths a `<key> = @( ... )` entry lists, one per
# line, in the order listed. Reads the entry up to its closing parenthesis and takes each
# single- or double-quoted path from it. No file, or no such key, prints nothing. overlays_load
# reads Overlays with it; macos/deploy-secrets.sh reads SearchRoots, which is no overlay's.
psd1_paths() {
    [ -f "$1" ] || return 0
    awk -v key="$2" '/^[[:space:]]*#/ { next }
         $0 ~ key "[[:space:]]*=" { on = 1; sub(".*" key "[[:space:]]*=", "") }
         on { print }
         on && /\)/ { exit }' "$1" |
        grep -oE "'[^']*'|\"[^\"]*\"" | sed -e 's/^.//' -e 's/.$//' |
        while IFS= read -r _ov_dir; do _overlay_path "$_ov_dir"; done
}

# _overlay_path <path>: a listed path as sh reads it. A drive path is converted where cygpath
# exists, and a leading ~/ is the home directory, as PowerShell reads them. A trailing separator
# is dropped: it would make every link source differ from what readlink reports, so --check
# would see drift forever and the prune would never match.
_overlay_path() {
    _ov_path="$1"
    case "$_ov_path" in
        [A-Za-z]:*) command -v cygpath > /dev/null 2>&1 && _ov_path="$(cygpath -u "$_ov_path")" ;;
        '~/'*) _ov_path="$HOME/${_ov_path#??}" ;;
    esac
    printf '%s\n' "${_ov_path%/}"
}

# overlays_load <repo> [overlay...]: read the overlays <repo>/ai/secrets/machine.local.psd1 lists,
# or take the ones passed instead, so a writer can check a list before writing it. Sets:
#   OVERLAYS       the overlays, one per line, in order
#   OVERLAY_KEY    the machine's name as machines/ files are named: COMPUTERNAME on Windows; on a
#                  Mac the HostName, else the LocalHostName, which Bonjour renames on its own
#                  (MACBOOK becomes MACBOOK-2) while another Mac has it. Up to its first dot,
#                  uppercased; empty for a machine with no name.
#   OVERLAY_REPOS  the git repositories the overlays are in, each once, in the order first listed
# An overlay that does not exist returns 1 and names it: skipping it would drop everything it
# carries. OVERLAYS still holds the list then, and nothing else may be asked of the module. Run it
# in the caller's shell, never inside $(...), or nothing it sets survives.
overlays_load() {
    OVERLAYS_LOADED=""
    OVERLAYS_BASE="$1"
    _ov_local="$1/ai/secrets/machine.local.psd1"
    shift
    if [ $# -gt 0 ]; then
        OVERLAYS="$(for _ov_dir in "$@"; do _overlay_path "$_ov_dir"; done)"
        _ov_from=""
    else
        OVERLAYS="$(psd1_paths "$_ov_local" Overlays)"
        _ov_from=" listed in $_ov_local"
    fi
    while IFS= read -r _ov_dir; do
        [ -z "$_ov_dir" ] || [ -d "$_ov_dir" ] || { printf 'overlay %s%s does not exist\n' "$_ov_dir" "$_ov_from" >&2; return 1; }
    done <<EOF
$OVERLAYS
EOF
    OVERLAY_KEY="$(if [ -n "${COMPUTERNAME:-}" ]; then
            printf '%s\n' "$COMPUTERNAME"
        elif command -v scutil > /dev/null 2>&1; then
            scutil --get HostName 2> /dev/null || scutil --get LocalHostName 2> /dev/null
        fi | sed 's/\..*//' | tr '[:lower:]' '[:upper:]')"
    OVERLAY_REPOS="$(printf '%s\n' "$OVERLAYS" | while IFS= read -r _ov_dir; do
        [ -z "$_ov_dir" ] || git -C "$_ov_dir" rev-parse --show-toplevel 2> /dev/null
    done | awk '!seen[$0]++')"
    OVERLAYS_LOADED=1
}

# _overlay_row <path> <count...>: look a path up in OVERLAY_TABLE, setting _ov_count to its count
# and _ov_roots to the roots it is read from, one per line. Returns 1 for a path not in the table
# or with a count not among those given, and 2 before overlays_load.
_overlay_row() {
    [ -n "${OVERLAYS_LOADED:-}" ] || { printf '%s: run overlays_load first\n' "$1" >&2; return 2; }
    _ov_rule="$(printf '%s\n' "$OVERLAY_TABLE" | awk -v p="$1" '$1 == p { print $2, $3 }')"
    [ -n "$_ov_rule" ] || { printf '%s is not a path an overlay may ship (OVERLAY_TABLE)\n' "$1" >&2; return 1; }
    _ov_count="${_ov_rule% *}"
    _ov_want="$1"; shift
    case " $* " in
        *" $_ov_count "*) ;;
        *) printf '%s is a %s path, not %s\n' "$_ov_want" "$_ov_count" "$*" >&2; return 1 ;;
    esac
    _ov_roots="$OVERLAYS"
    [ "${_ov_rule#* }" = "overlays" ] || _ov_roots="$OVERLAYS_BASE${OVERLAYS:+
$OVERLAYS}"
}

# overlay_sources <path>: print the sources of a one or all path, one per line. A one path prints
# none or one, and two sources print an error naming both and return 1; an all path never fails,
# so it may be piped. A path not in the table returns 1, and before overlays_load, 2.
#   x="$(overlay_sources ssh/authorized_keys)" || exit 1
overlay_sources() {
    _overlay_row "$1" one all || return $?
    _ov_rel="$1"
    case "$_ov_rel" in
        *'{KEY}'*)
            [ -n "$OVERLAY_KEY" ] || return 0
            _ov_rel="${_ov_rel%%'{KEY}'*}$OVERLAY_KEY${_ov_rel#*'{KEY}'}" ;;
    esac
    _ov_kind=-f
    case "$_ov_rel" in */) _ov_kind=-d; _ov_rel="${_ov_rel%/}" ;; esac
    _ov_found=""
    while IFS= read -r _ov_root; do
        [ -n "$_ov_root" ] && [ "$_ov_kind" "$_ov_root/$_ov_rel" ] || continue
        if [ "$_ov_count" = "all" ]; then
            printf '%s\n' "$_ov_root/$_ov_rel"
        elif [ -n "$_ov_found" ]; then
            printf '%s is provided by more than one source: %s and %s\n' "$_ov_rel" "$_ov_found" "$_ov_root/$_ov_rel" >&2
            return 1
        else
            _ov_found="$_ov_root/$_ov_rel"
        fi
    done <<EOF
$_ov_roots
EOF
    [ -z "$_ov_found" ] || printf '%s\n' "$_ov_found"
}

# overlay_entries <pattern> [claimant...]: one line per match of an entries row in each overlay, in
# overlay order: its path, a tab, and what already ships that name, or nothing when it is free. A
# claimant is a folder whose own entry of the same name claims it before any overlay's. Names
# compare without case, as they do on the NTFS the links live on. A clash is data, never a failure.
overlay_entries() {
    _overlay_row "$1" entries || return $?
    _ov_kind=-f
    _ov_pattern="$1"
    case "$_ov_pattern" in */) _ov_kind=-d; _ov_pattern="${_ov_pattern%/}" ;; esac
    _ov_dir="${_ov_pattern%/*}"
    _ov_leaf="${_ov_pattern##*/}"
    shift
    _ov_seen=""
    _ov_tab="$(printf '\t')"
    while IFS= read -r _ov_root; do
        [ -n "$_ov_root" ] || continue
        # The leaf unquoted, so it globs.
        for _ov_entry in "$_ov_root/$_ov_dir"/$_ov_leaf; do
            [ "$_ov_kind" "$_ov_entry" ] || continue
            _ov_name="${_ov_entry##*/}"
            _ov_key="$(printf '%s' "$_ov_name" | tr '[:upper:]' '[:lower:]')"
            _ov_clash=""
            for _ov_claimant in "$@"; do
                [ "$_ov_kind" "$_ov_claimant/$_ov_name" ] && { _ov_clash="$_ov_claimant/$_ov_name"; break; }
            done
            # "/" cannot appear in a name, so it ends the key unambiguously.
            [ -n "$_ov_clash" ] || case "$_ov_seen" in
                *"$_ov_tab$_ov_key/"*) _ov_clash="${_ov_seen#*"$_ov_tab$_ov_key/"}"; _ov_clash="${_ov_clash%%"$_ov_tab"*}" ;;
            esac
            [ -n "$_ov_clash" ] || _ov_seen="$_ov_seen$_ov_tab$_ov_key/$_ov_entry$_ov_tab"
            printf '%s\t%s\n' "$_ov_entry" "$_ov_clash"
        done
    done <<EOF
$_ov_roots
EOF
}

# merged_skill_registry: one line per skill in every ai/secrets/registry.psd1, the repo's first,
# its fields separated by REGISTRY_FS:
#   <id> <marker> <remote> <files, space-separated> <registry path>
# The same Id in two registries, in any case, is an error naming both, because either answer would
# be a guess. Keys are read without case and values in either quote, as PowerShell reads them, so an entry must
# put each key on a line of its own with a quoted value and Files as one @(...) on one line, as
# every registry here does. An entry it cannot read is an error naming the registry: no Id, no
# one-line Files, a key whose value is not a quoted string, or a Marker with no Remote, which would
# match every origin. Returns 1 on either error, 2 before overlays_load.
merged_skill_registry() {
    _ov_registries="$(overlay_sources ai/secrets/registry.psd1)" || return $?
    _ov_skills="$(printf '%s\n' "$_ov_registries" | while IFS= read -r _ov_registry; do
        [ -n "$_ov_registry" ] && _registry_entries "$_ov_registry"
    done)"
    _ov_bad="$(printf '%s\n' "$_ov_skills" | awk -F "$REGISTRY_FS" '$1 == "!" { print $2; exit }')"
    if [ -n "$_ov_bad" ]; then
        printf '%s has an entry this cannot read: each key on a line of its own with a quoted value, an Id, Files as one @(...) on one line, and a Remote beside every Marker\n' "$_ov_bad" >&2
        return 1
    fi
    # Ids compare without case, as PowerShell's hashtable compares them.
    _ov_twice="$(printf '%s\n' "$_ov_skills" | awk -F "$REGISTRY_FS" 'NF { id = tolower($1); if (id in seen) { print $1 " is registered in both " seen[id] " and " $5; exit } seen[id] = $5 }')"
    [ -z "$_ov_twice" ] || { printf 'skill %s\n' "$_ov_twice" >&2; return 1; }
    [ -z "$_ov_skills" ] || printf '%s\n' "$_ov_skills"
}

# _registry_entries <registry.psd1>: merged_skill_registry's lines for one registry, or "!" and
# the registry path for an entry it cannot read.
_registry_entries() {
    awk -v registry="$1" -v fs="$REGISTRY_FS" -v sq="'" '
        # every quoted string in text, space-separated
        function quoted(text,    out) {
            out = ""
            while (match(text, sq "[^" sq "]*" sq "|\"[^\"]*\"")) {
                out = out (out == "" ? "" : " ") substr(text, RSTART + 1, RLENGTH - 2)
                text = substr(text, RSTART + RLENGTH)
            }
            return out
        }
        # what follows "<key> =" on this line, or "" when the key is not on it
        function after(key,    lower) {
            lower = tolower($0)
            if (!match(lower, "(^|[^a-z])" key "[[:space:]]*=")) return ""
            return substr($0, RSTART + RLENGTH) "\n"
        }
        # the quoted value of key on this line; a key whose value is not one marks the entry bad
        function value(key, current,    rest) {
            if ((rest = after(key)) == "") return current
            if (match(rest, "^[[:space:]]*(" sq "[^" sq "]*" sq "|\"[^\"]*\")")) return quoted(substr(rest, RSTART, RLENGTH))
            bad = 1
            return current
        }
        function emit() {
            if (!open) return
            if (bad || id == "" || files == "" || (marker != "" && remote == "")) print "!" fs registry
            else print id fs marker fs remote fs files fs registry
            open = 0
        }
        /^[[:space:]]*#/ { next }
        tolower($0) ~ /skills[[:space:]]*=/ { skills = 1 }
        skills && /@\{/ { emit(); open = 1; bad = 0; id = marker = remote = files = "" }
        open {
            id = value("id", id)
            marker = value("marker", marker)
            remote = value("remote", remote)
            if ((rest = after("files")) != "") {
                if (match(rest, /^[[:space:]]*@\([^)]*\)/)) files = quoted(substr(rest, RSTART, RLENGTH))
                else bad = 1
            }
        }
        END { emit() }
    ' "$1"
}
