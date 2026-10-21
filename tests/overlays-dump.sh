#!/bin/sh

# overlays-dump.sh <repo>: everything ai/helpers/overlays.sh reads for <repo>, one fact per line,
# tab-separated, walking OVERLAY_RULES in order. tests/Dump-Overlays.ps1 prints the same for
# powershell/overlays.ps1, and tests/overlays-parity.test.sh diffs the two. Test-only.
#
#   key <machine key>             overlay <path>               repo <overlay repository>
#   <rule path> <source>          <rule path> !error           a one path with two sources
#   <rule path> <entry> <clash>   an entries path, its claimant <repo>/<rule path>
#   skill <id> <marker> <remote> <files> <secrets dir>, or skill !error

. "$(dirname "$0")/../ai/helpers/overlays.sh"

overlays_load "$1" || exit 1
printf 'key\t%s\n' "$OVERLAY_KEY"
printf '%s\n' "$OVERLAYS" | while IFS= read -r overlay; do [ -z "$overlay" ] || printf 'overlay\t%s\n' "$overlay"; done
printf '%s\n' "$OVERLAY_REPOS" | while IFS= read -r root; do [ -z "$root" ] || printf 'repo\t%s\n' "$root"; done

printf '%s\n' "$OVERLAY_RULES" | while read -r path count roots; do
    if [ "$count" = "entries" ]; then
        overlay_entries "$path" "$1/$path" | while IFS= read -r line; do printf '%s\t%s\n' "$path" "$line"; done
    elif sources="$(overlay_sources "$path" 2> /dev/null)"; then
        printf '%s\n' "$sources" | while IFS= read -r source; do [ -z "$source" ] || printf '%s\t%s\n' "$path" "$source"; done
    else
        printf '%s\t!error\n' "$path"
    fi
done

if skills="$(merged_skill_registry 2> /dev/null)"; then
    printf '%s\n' "$skills" | while IFS="$REGISTRY_FS" read -r id marker remote files registry; do
        [ -z "$id" ] || printf 'skill\t%s\t%s\t%s\t%s\t%s\n' "$id" "$marker" "$remote" "$files" "${registry%/registry.psd1}/$id"
    done
else
    printf 'skill\t!error\n'
fi
