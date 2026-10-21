#!/bin/sh

# ~/.aws/config in sh: every aws/config among the repo and the overlays, merged into one generated
# file. Sourced by macos/setup.sh after output.sh and managed-link.sh. powershell/aws-config.ps1 is
# the same file in PowerShell (docs/adr/0010-aws-config-is-generated.md).
#
# The AWS CLI reads one config file and has no include, so several sources cannot be one link. The
# file opens with a header, which is how a later run tells its own file, replaced freely, from one
# someone else wrote, which is backed up first. Each source goes in under a line naming it, in the
# order of the roots: the repo first, then the overlays as machine.local.psd1 lists them.
#
# POSIX sh has no `local`: these assign in the caller's shell. aws_config_check sets CHECK_FAILED=1
# on drift.

AWS_CONFIG_HEADER_PREFIX='# Written by dotfiles from '

# aws_config_sources <roots, one per line>: each root's aws/config that exists, one per line.
aws_config_sources() {
    while IFS= read -r root; do
        [ -n "$root" ] && [ -f "$root/aws/config" ] && printf '%s\n' "$root/aws/config"
    done <<EOF
$1
EOF
}

# aws_config_clash <sources>: the first section two sources both declare, as
# "[section] is in both <first> and <second>", or nothing. Spacing inside a name does not count.
aws_config_clash() {
    clash_sources="$1"
    set --
    while IFS= read -r source; do
        [ -n "$source" ] && set -- "$@" "$source"
    done <<EOF
$clash_sources
EOF
    [ $# -gt 0 ] || return 0
    awk '{ sub(/\r$/, "") }
         /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
             name = $0
             sub(/^[[:space:]]*\[[[:space:]]*/, "", name)
             sub(/[[:space:]]*\][[:space:]]*$/, "", name)
             gsub(/[[:space:]]+/, " ", name)
             if ((name in seen) && seen[name] != FILENAME) {
                 printf "[%s] is in both %s and %s\n", name, seen[name], FILENAME
                 exit
             }
             seen[name] = FILENAME
         }' "$@"
}

# aws_config_content <sources>: the merged file on stdout, with LF line endings.
aws_config_content() {
    count="$(printf '%s\n' "$1" | grep -c .)"
    printf '%s%s aws/config file(s); the next sync replaces any edit made here.\n' "$AWS_CONFIG_HEADER_PREFIX" "$count"
    printf '# Add a profile to one of them instead.\n'
    printf '%s\n' "$1" | while IFS= read -r source; do
        printf '\n# from %s\n' "$source"
        # Every line, the last one too when it has no newline, so the next source starts on its own.
        tr -d '\r' < "$source" | awk '{ print }'
    done
}

# aws_config_is_ours <dst>: true when dst is a regular file opening with the header
aws_config_is_ours() {
    [ -f "$1" ] && [ ! -L "$1" ] && head -n 1 "$1" | grep -q "^$AWS_CONFIG_HEADER_PREFIX"
}

# aws_config_is_leftover <dst>: true when dst is what this, or setup before it, put there: its own
# file, or a link to an aws/config. Anything else is someone's own.
aws_config_is_leftover() {
    if [ -L "$1" ]; then
        case "$(readlink "$1")" in */aws/config) return 0 ;; esac
        return 1
    fi
    aws_config_is_ours "$1"
}

# aws_config_apply <dst> <roots>: bring dst in line with the sources; report what it did. Returns 1
# when it could not, writing nothing on a clash.
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

    clash="$(aws_config_clash "$sources")"
    if [ -n "$clash" ]; then
        error "aws/config section $clash; ~/.aws/config left as it was"
        return 1
    fi

    mkdir -p "$(dirname "$1")" || return 1
    staged="$1.dotfiles-new"
    aws_config_content "$sources" > "$staged" || { rm -f "$staged"; return 1; }
    if [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$staged" "$1"; then
        rm -f "$staged"
        success "~/.aws/config already current"
        return 0
    fi

    if [ -L "$1" ]; then
        rm -f "$1"
    elif [ -e "$1" ] && ! aws_config_is_ours "$1"; then
        move_aside "$1" || { rm -f "$staged"; return 1; }
        warning "~/.aws/config was not written by dotfiles - backed it up to $backup"
    fi
    mv "$staged" "$1" || return 1
    success "~/.aws/config written from $(printf '%s\n' "$sources" | grep -c .) aws/config file(s); run 'aws sso login' to authenticate"
}

# aws_config_check <dst> <roots>: report the state of dst and change nothing
aws_config_check() {
    sources="$(aws_config_sources "$2")"
    if [ -z "$sources" ]; then
        if aws_config_is_leftover "$1"; then
            warning "~/.aws/config: no aws/config is left in this repo or an overlay; setup removes it"
            CHECK_FAILED=1
        fi
        return 0
    fi

    clash="$(aws_config_clash "$sources")"
    if [ -n "$clash" ]; then
        warning "aws/config section $clash"
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
        warning "~/.aws/config was not written by dotfiles; setup backs it up and replaces it"
        CHECK_FAILED=1
    elif [ "$(aws_config_content "$sources"; printf x)" != "$(cat "$1"; printf x)" ]; then
        warning "~/.aws/config is behind the aws/config files it merges"
        CHECK_FAILED=1
    else
        success "~/.aws/config"
    fi
}
