#!/bin/sh

# Reading ai/secrets/machine.local.psd1 from sh. Sourced by ai/install.sh and macos/.
# powershell/overlays.ps1 is the full reader; this is only enough to find the directories.

# psd1_paths <machine.local.psd1> <key>: the paths a `<key> = @( ... )` entry lists, one per
# line, in the order listed. Reads the entry up to its closing parenthesis and takes each
# single- or double-quoted path from it; a leading ~/ is the home directory, as PowerShell reads
# it. No file, or no such key, prints nothing.
psd1_paths() {
    [ -f "$1" ] || return 0
    awk -v key="$2" '/^[[:space:]]*#/ { next }
         $0 ~ key "[[:space:]]*=" { on = 1; sub(".*" key "[[:space:]]*=", "") }
         on { print }
         on && /\)/ { exit }' "$1" |
        grep -oE "'[^']*'|\"[^\"]*\"" | sed -e 's/^.//' -e 's/.$//' |
        while IFS= read -r dir; do
            case "$dir" in
                [A-Za-z]:*) command -v cygpath > /dev/null 2>&1 && dir="$(cygpath -u "$dir")" ;;
                '~/'*) dir="$HOME/${dir#??}" ;;
            esac
            # A trailing separator would make every link source path differ from what readlink
            # reports, so --check would see drift forever and the prune would never match.
            echo "${dir%/}"
        done
}
