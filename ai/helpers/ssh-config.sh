#!/bin/sh

# ~/.ssh/config in sh: every ssh/config among the repo and the overlays, merged into one generated
# file (ai/helpers/generated-file.sh), as ~/.aws/config is. Sourced by macos/setup.sh after
# generated-file.sh. macOS only, with no PowerShell counterpart
# (docs/adr/0011-ssh-config-is-generated.md).
#
# Each source goes in under a line naming it, in the order of the roots, the repo first and then the
# overlays as machine.local.psd1 lists them; a root listed twice goes in once. ssh keeps the first
# value it finds for a setting, so for a setting two sources both give, the earlier one wins. A line
# belongs to the Host or Match block above it, Include too, so each source opens with `Match all`,
# which puts it back in global scope however the one before it ended.
#
# With no source, a file this wrote and nobody edited is removed; any other ~/.ssh/config stays.
# Every apply sets ~/.ssh to mode 700 and the file to 600; the check compares content, not modes,
# which Git Bash, where the suite also runs, cannot hold.
#
# POSIX sh has no `local`: these assign in the caller's shell. ssh_config_check sets CHECK_FAILED=1
# on drift.

# ssh_config_body <sources>: what follows the checksum line
ssh_config_body() {
    printf '# Add a host to one of them instead.\n'
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] || continue
        printf '\n# from %s\nMatch all\n' "$source"
        generated_file_lines "$source"
    done
}

# ssh_config_apply <dst> <roots>: bring dst in line with the sources; report what it did. Returns 1
# when it could not, writing nothing.
ssh_config_apply() {
    sources="$(generated_file_sources ssh/config "$2")"
    if [ -z "$sources" ]; then
        if generated_file_is_ours "$1"; then
            rm -f "$1" && success "~/.ssh/config removed: no ssh/config is left in this repo or an overlay"
        else
            info "SSH config: neither this repo nor an overlay has ssh/config; skipped"
        fi
        return 0
    fi

    unreadable="$(generated_file_unreadable "$sources")"
    if [ -n "$unreadable" ]; then
        error "cannot read $unreadable; ~/.ssh/config left as it was"
        return 1
    fi

    mkdir -p "$(dirname "$1")" && chmod 700 "$(dirname "$1")" || return 1
    generated_file_apply "$1" "~/.ssh/config" ssh/config ssh_config_body "$sources" \
        "~/.ssh/config written from $(printf '%s\n' "$sources" | grep -c .) ssh/config file(s)" || return 1
    chmod 600 "$1"
}

# ssh_config_check <dst> <roots>: report the state of dst and change nothing
ssh_config_check() {
    sources="$(generated_file_sources ssh/config "$2")"
    if [ -z "$sources" ]; then
        if generated_file_is_ours "$1"; then
            warning "~/.ssh/config: no ssh/config is left in this repo or an overlay; setup removes it"
            CHECK_FAILED=1
        fi
        return 0
    fi

    unreadable="$(generated_file_unreadable "$sources")"
    if [ -n "$unreadable" ]; then
        warning "cannot read $unreadable"
        CHECK_FAILED=1
        return 0
    fi

    generated_file_check "$1" "~/.ssh/config" ssh/config ssh_config_body "$sources"
}
