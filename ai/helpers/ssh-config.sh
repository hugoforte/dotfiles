#!/bin/sh

# ~/.ssh/config in sh: every ssh/config among the repo and the overlays, merged into one generated
# file (ai/helpers/generated-file.sh), as ~/.aws/config is. Sourced by macos/setup.sh after
# generated-file.sh. macOS only, with no PowerShell counterpart
# (docs/adr/0011-ssh-config-is-generated.md).
#
# Each source goes in under a line naming it, in the order given, which overlay_sources ssh/config
# gives as the repo first and then the overlays as machine.local.psd1 lists them; a file given twice
# goes in once. ssh keeps the first
# value it finds for a setting, so for a setting two sources both give, the earlier one wins. A line
# belongs to the Host or Match block above it, Include too, so each source opens with `Match all`,
# which puts it back in global scope however the one before it ended.
#
# With no source, a file this wrote and nobody edited is removed; any other ~/.ssh/config stays.
# Every apply sets ~/.ssh to mode 700 and the file to 600. The check compares content, and reports
# either one writable by group or others, which ssh refuses for the file; but not on Git Bash,
# where the suite also runs and which holds no Unix modes.
#
# POSIX sh has no `local`: these assign in the caller's shell. ssh_config_check sets CHECK_FAILED=1
# on drift.

# Git Bash (MSYS) holds no Unix modes, so there the check leaves them be.
SSH_CONFIG_HOLDS_MODES=true
case "$(uname -s)" in
    MINGW*|MSYS*) SSH_CONFIG_HOLDS_MODES=false ;;
esac

# ssh_config_writable_by_others <path>: true when its group or others may write to it
ssh_config_writable_by_others() {
    case "$(ls -ld "$1" | cut -c6,9)" in
        *w*) return 0 ;;
    esac
    return 1
}

# ssh_config_body <sources>: what follows the checksum line
ssh_config_body() {
    printf '# Add a host to one of them instead.\n'
    printf '%s\n' "$1" | while IFS= read -r source; do
        [ -n "$source" ] || continue
        printf '\n# from %s\nMatch all\n' "$source"
        generated_file_lines "$source"
    done
}

# ssh_config_apply <dst> <ssh/config files>: bring dst in line with them; report what it did.
# Returns 1 when it could not, writing nothing.
ssh_config_apply() {
    sources="$(generated_file_sources "$2")"
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

    mkdir -p "$(dirname "$1")" || return 1
    if ! chmod 700 "$(dirname "$1")"; then
        error "could not set ~/.ssh to mode 700"
        return 1
    fi
    generated_file_apply "$1" "~/.ssh/config" ssh/config ssh_config_body "$sources" \
        "~/.ssh/config written from $(printf '%s\n' "$sources" | grep -c .) ssh/config file(s)" \
        back-up-links 600
}

# ssh_config_check <dst> <ssh/config files>: report the state of dst and change nothing
ssh_config_check() {
    sources="$(generated_file_sources "$2")"
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
    [ "$SSH_CONFIG_HOLDS_MODES" = "true" ] || return 0
    if [ -d "$(dirname "$1")" ] && ssh_config_writable_by_others "$(dirname "$1")"; then
        warning "~/.ssh is writable by group or others; setup sets it to 700"
        CHECK_FAILED=1
    fi
    if [ -f "$1" ] && [ ! -L "$1" ] && ssh_config_writable_by_others "$1"; then
        warning "~/.ssh/config is writable by group or others, so ssh refuses it; setup sets it to 600"
        CHECK_FAILED=1
    fi
}
