#!/bin/sh

# The managed link in sh: link, unlink_managed, check_link, and the orphan prune.
# Sourced by ai/install.sh and macos/setup.sh after output.sh. powershell/managed-link.ps1 is the
# same policy in PowerShell (docs/adr/0003-back-up-then-link.md).
#
# POSIX sh has no `local`: these assign src, dst, backup and actual in the caller's shell.
# check_link and check_orphans set CHECK_FAILED=1 on drift; the caller reads it.

# On Git Bash (MSYS), `ln -s` silently copies unless native symlinks are enabled.
# Native symlinks need Windows Developer Mode or an elevated shell.
# NTFS ignores case in a path, and Git Bash keeps whatever capitals a path was typed with, so
# there two spellings of one checkout must compare equal.
FOLD_PATH_CASE=false
case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS="winsymlinks:nativestrict"; FOLD_PATH_CASE=true ;;
esac

CHECK_FAILED=0

# move_aside <dst> [backup dir]: move the real file at dst out of the way, never deleting it, under
# the same <leaf>.backup.<timestamp> name powershell/managed-link.ps1 uses, so one convention shows
# up in both languages. It goes beside dst, or into the backup dir when one is given, as
# deploy-secrets does to keep displaced plaintext out of a checkout. Sets backup to where it went.
move_aside() {
    backup="$1.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -n "$2" ]; then
        mkdir -p "$2" || { error "Could not make $2 for a backup of $1 - leaving it alone"; return 1; }
        backup="$2/${backup##*/}"
    fi
    # mv replaces what is there; a backup taken in the same second as another is numbered.
    backup_base="$backup"; backup_n=1
    while [ -e "$backup" ] || [ -L "$backup" ]; do
        backup="$backup_base.$backup_n"; backup_n=$((backup_n + 1))
    done
    if ! mv "$1" "$backup"; then
        error "Could not move $1 aside to $backup - leaving it alone"
        return 1
    fi
}

# link <src> <dst> [backup dir]: point dst at src, backing up whatever real file was already there.
# A symlink at dst holds no content of its own, so it is replaced without a backup. A real file
# is someone's work, and is moved aside.
link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        move_aside "$dst" "$3" || return 1
        warning "$dst was not a symlink - backed it up to $backup"
    fi
    ln -s "$src" "$dst"
}

# same_path <a> <b>: true when both spell the same path (without case on Windows)
same_path() {
    if [ "$FOLD_PATH_CASE" = "true" ]; then
        [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ]
    else
        [ "$1" = "$2" ]
    fi
}

# is_link_to <src> <dst>: true when dst is a symlink to src
is_link_to() {
    [ -L "$2" ] && same_path "$(readlink "$2")" "$1"
}

# unlink_managed <src> <dst>: remove dst only if it is a symlink to src. A link someone pointed
# elsewhere at the same name is theirs: it is left in place, said, and the call returns 1.
unlink_managed() {
    [ -L "$2" ] || return 0
    if is_link_to "$1" "$2"; then
        rm -f "$2"
    else
        warning "$2 -> $(readlink "$2") (expected $1), left in place"
        return 1
    fi
}

# is_orphan_link <entry> <source_dir>: true when <entry> is a symlink into
# <source_dir> that no longer resolves. A skill or agent deleted from the repo
# leaves exactly this behind on every machine that had linked it, and a
# dangling link is not harmless: the agents still list the name and then fail
# to read it. Links pointing anywhere else are somebody else's business.
is_orphan_link() {
    [ -L "$1" ] || return 1
    [ -e "$1" ] && return 1
    case "$(readlink "$1")" in
        "$2"/*) return 0 ;;
    esac
    return 1
}

# prune_orphans <dir> <source_dir>: delete the orphans in <dir>
prune_orphans() {
    [ -d "$1" ] || return 0
    for entry in "$1"/*; do
        is_orphan_link "$entry" "$2" || continue
        rm -f "$entry"
        success "Removed stale link $entry"
    done
}

# check_link <src> <dst>: report the state of one managed link
check_link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        actual="$(readlink "$dst")"
        if same_path "$actual" "$src"; then
            success "$dst"
        else
            warning "$dst -> $actual (expected $src)"
            CHECK_FAILED=1
        fi
    elif [ -e "$dst" ]; then
        warning "$dst is a regular file or directory, not a symlink"
        CHECK_FAILED=1
    else
        warning "$dst missing"
        CHECK_FAILED=1
    fi
}

# check_orphans <dir> <source_dir>: report the orphans in <dir> as drift
check_orphans() {
    [ -d "$1" ] || return 0
    for entry in "$1"/*; do
        is_orphan_link "$entry" "$2" || continue
        warning "$entry is a stale link to something no longer in the repo"
        CHECK_FAILED=1
    done
}
