#!/bin/sh

# The generated file in sh: a managed path that holds what dotfiles writes from several sources,
# where a link could have only one. Sourced by macos/setup.sh after output.sh and managed-link.sh,
# for ai/helpers/aws-config.sh and ai/helpers/ssh-config.sh. powershell/generated-file.ps1 is the
# same policy in PowerShell (docs/adr/0010-aws-config-is-generated.md).
#
# The file opens with a header, then a checksum of what follows it. A file with both, still
# matching, is this one's own and is replaced freely; anything else is someone's, and is backed up
# first (docs/adr/0003-back-up-then-link.md). The checksum is there because another program may
# edit the file by appending, as aws configure sso does, which leaves the header as it was. A link
# that setup used to make holds no content of its own, so it is replaced without a backup; one
# only its owner can have made is backed up.
#
# POSIX sh has no `local`: these assign in the caller's shell. generated_file_check sets
# CHECK_FAILED=1 on drift.

GENERATED_FILE_HEADER_PREFIX='# Written by dotfiles from '
GENERATED_FILE_CHECKSUM_PREFIX='# dotfiles-cksum: '
GENERATED_FILE_BOM="$(printf '\357\273\277')"

# generated_file_sources <relative path> <roots, one per line>: each root's file at that path that
# exists, one per line, each file once however its root was spelled.
generated_file_sources() {
    while IFS= read -r root; do
        [ -n "$root" ] && [ -f "$root/$1" ] || continue
        printf '%s/%s\n' "$(cd "$(dirname "$root/$1")" && pwd -P)" "${1##*/}"
    done <<EOF | awk '!seen[$0]++'
$2
EOF
}

# generated_file_unreadable <sources>: the first source that cannot be read, or nothing
generated_file_unreadable() {
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] && [ ! -r "$source" ] && { printf '%s\n' "$source"; break; }
    done
}

# generated_file_lines <source>: the source as it goes into the file: without a byte-order mark,
# which a reader may reject mid-file, with LF line endings, and with every line ended, the last one
# too, so the next source starts on its own.
generated_file_lines() {
    LC_ALL=C sed "1s/^$GENERATED_FILE_BOM//" "$1" | tr -d '\r' | awk '{ print }'
}

# generated_file_checksum < file: the checksum line's value for what is read
generated_file_checksum() {
    cksum | awk '{ print $1 "-" $2 }'
}

# generated_file_write <relative path> <body function> <sources> <file>: the header, the checksum
# and what <body function> <sources> prints, into <file>
generated_file_write() {
    body_file="$4.body"
    "$2" "$3" > "$body_file" || { rm -f "$body_file"; return 1; }
    {
        printf '%s%s %s file(s); the next sync replaces any edit made here.\n' \
            "$GENERATED_FILE_HEADER_PREFIX" "$(printf '%s\n' "$3" | grep -c .)" "$1"
        printf '%s%s\n' "$GENERATED_FILE_CHECKSUM_PREFIX" "$(generated_file_checksum < "$body_file")"
        cat "$body_file"
    } > "$4"
    write_status=$?
    rm -f "$body_file"
    return $write_status
}

# generated_file_is_ours <dst>: true when dst is a regular file this wrote and nobody has edited
# since: its header, then a checksum that matches what follows it
generated_file_is_ours() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    head -n 1 "$1" | grep -q "^$GENERATED_FILE_HEADER_PREFIX" || return 1
    recorded="$(sed -n "2s/^$GENERATED_FILE_CHECKSUM_PREFIX//p" "$1")"
    [ -n "$recorded" ] && [ "$recorded" = "$(tail -n +3 "$1" | generated_file_checksum)" ]
}

# generated_file_apply <dst> <label> <relative path> <body function> <sources> <written message>
# <links>: bring dst in line with the sources; report what it did. Returns 1 when it could not.
# <links> is replace-links where a link at dst can only be one an earlier setup made, which is
# removed, or back-up-links where it can only be someone's own, which is moved aside like a file.
generated_file_apply() {
    mkdir -p "$(dirname "$1")" || return 1
    staged="$1.dotfiles-new"
    generated_file_write "$3" "$4" "$5" "$staged" || { rm -f "$staged"; return 1; }
    if [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$staged" "$1"; then
        rm -f "$staged"
        success "$2 already current"
        return 0
    fi

    if [ -L "$1" ] && [ "$7" = "back-up-links" ]; then
        link_target="$(readlink "$1")"
        move_aside "$1" || { rm -f "$staged"; return 1; }
        warning "$2 was a link to $link_target - moved it aside to $backup"
    elif [ -L "$1" ]; then
        rm -f "$1"
    elif [ -e "$1" ] && ! generated_file_is_ours "$1"; then
        move_aside "$1" || { rm -f "$staged"; return 1; }
        warning "$2 was not written by dotfiles, or was edited - backed it up to $backup"
    fi
    mv "$staged" "$1" || { rm -f "$staged"; return 1; }
    success "$6"
}

# generated_file_check <dst> <label> <relative path> <body function> <sources>: report the state
# of dst and change nothing
generated_file_check() {
    if [ -L "$1" ]; then
        warning "$2 is a link, not the merged file; setup replaces it"
        CHECK_FAILED=1
    elif [ ! -e "$1" ]; then
        warning "$2 missing"
        CHECK_FAILED=1
    elif ! generated_file_is_ours "$1"; then
        warning "$2 was not written by dotfiles, or was edited; setup backs it up and replaces it"
        CHECK_FAILED=1
    else
        expected="$(mktemp)" || return 1
        generated_file_write "$3" "$4" "$5" "$expected"
        if cmp -s "$expected" "$1"; then
            success "$2"
        else
            warning "$2 is behind the $3 files it merges"
            CHECK_FAILED=1
        fi
        rm -f "$expected"
    fi
}
