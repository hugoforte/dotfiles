#!/bin/sh

# ~/.aws/config in sh: every aws/config among the repo and the overlays, merged into one generated
# file (ai/helpers/generated-file.sh). Sourced by macos/setup.sh after generated-file.sh.
# powershell/aws-config.ps1 is the same file in PowerShell (docs/adr/0010-aws-config-is-generated.md).
#
# The AWS CLI reads one config file and has no include, so several sources cannot be one link. Each
# source goes in under a line naming it, in the order of the roots, the repo first and then the
# overlays as machine.local.psd1 lists them; a root listed twice goes in once. The same section in
# two sources, as the AWS CLI names sections, is an error naming both, and nothing is written.
# With no source left, the file this wrote is removed, and so is a link left dangling.
#
# POSIX sh has no `local`: these assign in the caller's shell. aws_config_check sets CHECK_FAILED=1
# on drift.

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
    LC_ALL=C awk -v bom="$GENERATED_FILE_BOM" '
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

# aws_config_body <sources>: what follows the checksum line
aws_config_body() {
    printf '# Add a profile to one of them instead.\n'
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] || continue
        printf '\n# from %s\n' "$source"
        generated_file_lines "$source"
    done
}

# aws_config_is_leftover <dst>: true when dst is what this, or setup before it, left behind: its
# own file, or a link that no longer resolves. A live link is someone's own, and stays.
aws_config_is_leftover() {
    if [ -L "$1" ]; then
        [ ! -e "$1" ]
    else
        generated_file_is_ours "$1"
    fi
}

# aws_config_problem <sources>: what stops the merge, or nothing
aws_config_problem() {
    unreadable="$(generated_file_unreadable "$1")"
    if [ -n "$unreadable" ]; then
        printf 'cannot read %s\n' "$unreadable"
        return
    fi
    clash="$(aws_config_clash "$1")"
    [ -z "$clash" ] || printf 'aws/config section %s\n' "$clash"
}

# aws_config_apply <dst> <roots>: bring dst in line with the sources; report what it did. Returns 1
# when it could not, writing nothing.
aws_config_apply() {
    sources="$(generated_file_sources aws/config "$2")"
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

    generated_file_apply "$1" "~/.aws/config" aws/config aws_config_body "$sources" \
        "~/.aws/config written from $(printf '%s\n' "$sources" | grep -c .) aws/config file(s); run 'aws sso login' to authenticate" \
        replace-links
}

# aws_config_check <dst> <roots>: report the state of dst and change nothing
aws_config_check() {
    sources="$(generated_file_sources aws/config "$2")"
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

    generated_file_check "$1" "~/.aws/config" aws/config aws_config_body "$sources"
}
