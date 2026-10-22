#!/bin/sh

# ~/.aws/config in sh: every aws/config among the repo and the overlays, merged into one generated
# file. Sourced by macos/setup.sh after output.sh and managed-link.sh. powershell/aws-config.ps1 is
# the same file in PowerShell (docs/adr/0010-aws-config-is-generated.md).
#
# The AWS CLI reads one config file and has no include, so several sources cannot be one link. Each
# source goes in under a line naming it, in the order given, which overlay_sources aws/config gives
# as the repo first and then the overlays as machine.local.psd1 lists them; a file given twice goes
# in once. The same section in
# two sources, as the AWS CLI names sections, is an error naming both, and nothing is written.
#
# The file opens with a header, then a checksum of what follows it. A file with both, still
# matching, is this one's own and is replaced freely; anything else is someone's, and is backed up
# first. The checksum is there because the AWS CLI edits the file by appending (aws configure sso),
# which leaves the header as it was. With no source left, the file this wrote is removed, and so is
# a link left dangling.
#
# POSIX sh has no `local`: these assign in the caller's shell. aws_config_check sets CHECK_FAILED=1
# on drift.

AWS_CONFIG_HEADER_PREFIX='# Written by dotfiles from '
AWS_CONFIG_CHECKSUM_PREFIX='# dotfiles-cksum: '
AWS_CONFIG_BOM="$(printf '\357\273\277')"

# aws_config_sources <aws/config files, one per line>: each that exists, one per line, each file
# once however it was spelled.
aws_config_sources() {
    while IFS= read -r file; do
        [ -n "$file" ] && [ -f "$file" ] || continue
        printf '%s/%s\n' "$(cd "$(dirname "$file")" && pwd -P)" "${file##*/}"
    done <<EOF | awk '!seen[$0]++'
$1
EOF
}

# aws_config_unreadable <sources>: the first source that cannot be read, or nothing
aws_config_unreadable() {
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] && [ ! -r "$source" ] && { printf '%s\n' "$source"; break; }
    done
}

# aws_config_clash <sources>: the first section two sources both declare, as
# "[section] is in both <first> and <second>", or nothing. A section is named as the AWS CLI names
# it: the header up to the last ] on its line, its words with spacing collapsed, a quoted name
# unquoted, and [default] the same profile as [profile default].
aws_config_clash() {
    clash_sources="$1"
    set --
    while IFS= read -r source; do
        [ -n "$source" ] && set -- "$@" "$source"
    done <<EOF
$clash_sources
EOF
    [ $# -gt 0 ] || return 0
    LC_ALL=C awk -v bom="$AWS_CONFIG_BOM" '
        { sub(/\r$/, "") }
        FNR == 1 && substr($0, 1, 3) == bom { $0 = substr($0, 4) }
        /^[[:space:]]*\[.*\]/ {
            header = $0
            sub(/^[[:space:]]*\[/, "", header)
            sub(/\][^]]*$/, "", header)
            n = split(header, w, /[[:space:]]+/)
            name = ""
            for (i = 1; i <= n; i++) if (w[i] != "") { gsub(/^["\047]|["\047]$/, "", w[i]); name = name (name == "" ? "" : " ") w[i] }
            if (name == "default") name = "profile default"
            if ((name in seen) && seen[name] != FILENAME) {
                printf "[%s] is in both %s and %s\n", name, seen[name], FILENAME
                exit
            }
            seen[name] = FILENAME
        }' "$@"
}

# aws_config_body <sources>: what follows the checksum line, with LF line endings
aws_config_body() {
    printf '# Add a profile to one of them instead.\n'
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] || continue
        printf '\n# from %s\n' "$source"
        # Without a byte-order mark, which the AWS CLI rejects mid-file, and every line, the last one
        # too when it has no newline, so the next source starts on its own.
        LC_ALL=C sed "1s/^$AWS_CONFIG_BOM//" "$source" | tr -d '\r' | awk '{ print }'
    done
}

# aws_config_checksum < file: the checksum line's value for what is read
aws_config_checksum() {
    cksum | awk '{ print $1 "-" $2 }'
}

# aws_config_write <sources> <file>: the merged file into <file>
aws_config_write() {
    body_file="$2.body"
    aws_config_body "$1" > "$body_file" || { rm -f "$body_file"; return 1; }
    {
        printf '%s%s aws/config file(s); the next sync replaces any edit made here.\n' \
            "$AWS_CONFIG_HEADER_PREFIX" "$(printf '%s\n' "$1" | grep -c .)"
        printf '%s%s\n' "$AWS_CONFIG_CHECKSUM_PREFIX" "$(aws_config_checksum < "$body_file")"
        cat "$body_file"
    } > "$2"
    write_status=$?
    rm -f "$body_file"
    return $write_status
}

# aws_config_is_ours <dst>: true when dst is a regular file this wrote and nobody has edited since:
# its header, then a checksum that matches what follows it
aws_config_is_ours() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    head -n 1 "$1" | grep -q "^$AWS_CONFIG_HEADER_PREFIX" || return 1
    recorded="$(sed -n "2s/^$AWS_CONFIG_CHECKSUM_PREFIX//p" "$1")"
    [ -n "$recorded" ] && [ "$recorded" = "$(tail -n +3 "$1" | aws_config_checksum)" ]
}

# aws_config_is_leftover <dst>: true when dst is what this, or setup before it, left behind: its
# own file, or a link that no longer resolves. A live link is someone's own, and stays.
aws_config_is_leftover() {
    if [ -L "$1" ]; then
        [ ! -e "$1" ]
    else
        aws_config_is_ours "$1"
    fi
}

# aws_config_problem <sources>: what stops the merge, or nothing
aws_config_problem() {
    unreadable="$(aws_config_unreadable "$1")"
    if [ -n "$unreadable" ]; then
        printf 'cannot read %s\n' "$unreadable"
        return
    fi
    clash="$(aws_config_clash "$1")"
    [ -z "$clash" ] || printf 'aws/config section %s\n' "$clash"
}

# aws_config_apply <dst> <aws/config files>: bring dst in line with them; report what it did. Returns 1
# when it could not, writing nothing.
aws_config_apply() {
    sources="$(aws_config_sources "$2")"
    if [ -z "$sources" ]; then
        if aws_config_is_leftover "$1"; then
            rm -f "$1" && success "~/.aws/config removed: no aws/config is left in this repo or an overlay"
        else
            info "AWS config: neither this repo nor an overlay has aws/config; skipped"
        fi
        return 0
    fi

    problem="$(aws_config_problem "$sources")"
    if [ -n "$problem" ]; then
        error "$problem; ~/.aws/config left as it was"
        return 1
    fi

    mkdir -p "$(dirname "$1")" || return 1
    staged="$1.dotfiles-new"
    aws_config_write "$sources" "$staged" || { rm -f "$staged"; return 1; }
    if [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$staged" "$1"; then
        rm -f "$staged"
        success "~/.aws/config already current"
        return 0
    fi

    if [ -L "$1" ]; then
        rm -f "$1"
    elif [ -e "$1" ] && ! aws_config_is_ours "$1"; then
        move_aside "$1" || { rm -f "$staged"; return 1; }
        warning "~/.aws/config was not written by dotfiles, or was edited - backed it up to $backup"
    fi
    mv "$staged" "$1" || { rm -f "$staged"; return 1; }
    success "~/.aws/config written from $(printf '%s\n' "$sources" | grep -c .) aws/config file(s); run 'aws sso login' to authenticate"
}

# aws_config_check <dst> <aws/config files>: report the state of dst and change nothing
aws_config_check() {
    sources="$(aws_config_sources "$2")"
    if [ -z "$sources" ]; then
        if aws_config_is_leftover "$1"; then
            warning "~/.aws/config: no aws/config is left in this repo or an overlay; setup removes it"
            CHECK_FAILED=1
        fi
        return 0
    fi

    problem="$(aws_config_problem "$sources")"
    if [ -n "$problem" ]; then
        warning "$problem"
        CHECK_FAILED=1
        return 0
    fi

    if [ -L "$1" ]; then
        warning "~/.aws/config is a link, not the merged file; setup replaces it"
        CHECK_FAILED=1
    elif [ ! -e "$1" ]; then
        warning "~/.aws/config missing"
        CHECK_FAILED=1
    elif ! aws_config_is_ours "$1"; then
        warning "~/.aws/config was not written by dotfiles, or was edited; setup backs it up and replaces it"
        CHECK_FAILED=1
    else
        expected="$(mktemp)" || return 1
        aws_config_write "$sources" "$expected"
        if cmp -s "$expected" "$1"; then
            success "~/.aws/config"
        else
            warning "~/.aws/config is behind the aws/config files it merges"
            CHECK_FAILED=1
        fi
        rm -f "$expected"
    fi
}
