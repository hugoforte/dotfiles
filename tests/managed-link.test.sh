#!/bin/sh

# Fixture suite for ai/helpers/managed-link.sh: link, unlink_managed, check_link.
#
# These three hold the sh half of the cross-language policy in hugoforte/dotfiles#6: a real
# file at a managed path is backed up and then linked, a symlink is replaced outright, and a
# check reports without touching anything. powershell/managed-link.ps1 is the other half, and
# tests/ManagedLink.Tests.ps1 covers it; the assertions here are deliberately the same shape.
# One difference: unlink_managed removes only a link to the source it is given, where
# Remove-ManagedLink removes any symlink at the path.
#
# The helper only defines functions, so it is sourced as it is. Everything else happens in a
# temp directory this suite creates and removes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# symlink_yn <path>: y when path is a symlink
symlink_yn() {
    if [ -L "$1" ]; then printf y; else printf n; fi
}

# exists_yn <path>: y when anything is there, symlink or not
exists_yn() {
    if [ -L "$1" ] || [ -e "$1" ]; then printf y; else printf n; fi
}

# real_file_yn <path>: y when a regular file is there and it is not a link
real_file_yn() {
    if [ -f "$1" ] && [ ! -L "$1" ]; then printf y; else printf n; fi
}

# mentions <text> <needle>: y when the needle appears in the text
# ("$2" is quoted in the pattern, so [ ] and * inside it match literally)
mentions() {
    case "$1" in
        *"$2"*) printf y ;;
        *)      printf n ;;
    esac
}

# backups_of <path>: the backups sitting beside path, one per line
backups_of() {
    for b in "$1".backup.*; do
        [ -e "$b" ] && printf '%s\n' "$b"
    done
}

# backup_count <path>: how many there are
backup_count() {
    backups_of "$1" | grep -c .
}

# snapshot <dir>: what the directory holds, as text - the same twice means nothing changed
snapshot() {
    for f in "$1"/* "$1"/.*; do
        case "${f##*/}" in .|..) continue ;; esac
        [ -L "$f" ] || [ -e "$f" ] || continue
        if [ -L "$f" ]; then
            printf 'link %s -> %s\n' "$f" "$(readlink "$f")"
        elif [ -f "$f" ]; then
            printf 'file %s %s\n' "$f" "$(cat "$f")"
        else
            printf 'other %s\n' "$f"
        fi
    done
}

# run_check <src> <dst>: check_link in this shell, not a subshell, so its CHECK_FAILED
# survives; its output lands in $check_out.
run_check() {
    CHECK_FAILED=0
    check_link "$1" "$2" > "$work/check.out" 2>&1
    check_out="$(cat "$work/check.out")"
}

. "$REPO_ROOT/ai/helpers/output.sh"
. "$REPO_ROOT/ai/helpers/managed-link.sh"

# ---------------------------------------------------------------------------
# Fake repo and fake home
#
# POSIX sh has no `local`, so the primitives assign src, dst, backup and actual in this very
# shell. Nothing here may be called any of those - hence repo and saved.
# ---------------------------------------------------------------------------

repo="$work/repo"
home="$work/home"
mkdir -p "$repo" "$home"
printf 'from the repo\n' > "$repo/CLAUDE.md"
printf 'some other file\n' > "$repo/other.md"

# ---------------------------------------------------------------------------
# link
# ---------------------------------------------------------------------------

printf '=== link ===\n'

fresh="$home/fresh.md"
link "$repo/CLAUDE.md" "$fresh" > /dev/null; rc=$?
assert_eq "link into an empty path succeeds" "0" "$rc"
assert_eq "... leaves a symlink" "y" "$(symlink_yn "$fresh")"
assert_eq "... pointing at the source" "$repo/CLAUDE.md" "$(readlink "$fresh")"
assert_eq "... that reads as the source" "from the repo" "$(cat "$fresh")"

link "$repo/CLAUDE.md" "$fresh" > /dev/null; rc=$?
assert_eq "linking again over the correct link succeeds" "0" "$rc"
assert_eq "... still a symlink to the source" "$repo/CLAUDE.md" "$(readlink "$fresh")"
assert_eq "... and backs nothing up" "0" "$(backup_count "$fresh")"

stale="$home/stale.md"
ln -s "$repo/other.md" "$stale"
link "$repo/CLAUDE.md" "$stale" > /dev/null; rc=$?
assert_eq "repointing a symlink that points elsewhere succeeds" "0" "$rc"
assert_eq "... at the new source" "$repo/CLAUDE.md" "$(readlink "$stale")"
assert_eq "... without backing the old symlink up" "0" "$(backup_count "$stale")"

# The policy change: this used to warn and return 1, leaving the file in place.
real="$home/real.md"
printf 'hand-written\n' > "$real"
out="$(link "$repo/CLAUDE.md" "$real")"; rc=$?
assert_eq "linking over a real file succeeds instead of refusing" "0" "$rc"
assert_eq "... leaves a symlink at the target" "y" "$(symlink_yn "$real")"
assert_eq "... that reads as the source" "from the repo" "$(cat "$real")"
assert_eq "... and leaves exactly one backup beside it" "1" "$(backup_count "$real")"

saved="$(backups_of "$real")"
assert_eq "the backup keeps the original content" "hand-written" "$(cat "$saved")"
assert_eq "the backup is a real file, not a link" "y" "$(real_file_yn "$saved")"
case "${saved##*/}" in
    real.md.backup.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]) named=y ;;
    *) named=n ;;
esac
assert_eq "the backup is named <leaf>.backup.<yyyymmdd_HHMMSS>, as managed-link.ps1 names it" "y" "$named"
assert_eq "link says where the backup went" "y" "$(mentions "$out" "$real.backup.")"

# ai/install.sh calls `link … && success …`; that branch has to run now that link succeeds.
chained="$home/chained.md"
printf 'hand-written\n' > "$chained"
if link "$repo/CLAUDE.md" "$chained" > /dev/null; then took=y; else took=n; fi
assert_eq "a caller's 'link … && success' branch runs after a backup" "y" "$took"

# A backup folder, as deploy-secrets uses to keep displaced plaintext out of a checkout.
elsewhere="$home/secret.env"
printf 'plaintext\n' > "$elsewhere"
out="$(link "$repo/CLAUDE.md" "$elsewhere" "$work/backups/checkout")"; rc=$?
assert_eq "linking with a backup folder succeeds" "0" "$rc"
assert_eq "... leaves no backup beside the target" "0" "$(backup_count "$elsewhere")"
set -- "$work/backups/checkout"/secret.env.backup.*
assert_eq "... and puts it in the folder, made if missing, under the same name" "plaintext" "$(cat "$1")"
assert_eq "... and says where it went" "y" "$(mentions "$out" "$work/backups/checkout/secret.env.backup.")"

# ---------------------------------------------------------------------------
# unlink_managed
# ---------------------------------------------------------------------------

printf '=== unlink_managed ===\n'

doomed="$home/doomed.md"
ln -s "$repo/CLAUDE.md" "$doomed"
unlink_managed "$repo/CLAUDE.md" "$doomed"
assert_eq "unlink_managed removes a symlink to the source" "n" "$(exists_yn "$doomed")"
assert_eq "... and leaves the source it pointed at" "from the repo" "$(cat "$repo/CLAUDE.md")"

theirs="$home/theirs.md"
ln -s "$repo/other.md" "$theirs"
unlink_managed "$repo/CLAUDE.md" "$theirs"
assert_eq "unlink_managed leaves a symlink someone pointed elsewhere" "$repo/other.md" "$(readlink "$theirs")"
rm -f "$theirs"

precious="$home/precious.md"
printf 'not yours to delete\n' > "$precious"
unlink_managed "$repo/CLAUDE.md" "$precious"
assert_eq "unlink_managed leaves a real file where it is" "y" "$(exists_yn "$precious")"
assert_eq "... with its content untouched" "not yours to delete" "$(cat "$precious")"

# ---------------------------------------------------------------------------
# check_link
# ---------------------------------------------------------------------------

printf '=== check_link ===\n'

wrong="$home/wrong.md"
ln -s "$repo/other.md" "$wrong"

# Taken before any check runs, and compared after the last one.
before="$(snapshot "$home")"

run_check "$repo/CLAUDE.md" "$fresh"
assert_eq "check_link passes a correct link" "0" "$CHECK_FAILED"
assert_eq "... and reports it as a success" "y" "$(mentions "$check_out" "[OK]")"

run_check "$repo/CLAUDE.md" "$home/absent.md"
assert_eq "check_link fails on a missing link" "1" "$CHECK_FAILED"
assert_eq "... and says it is missing" "y" "$(mentions "$check_out" "missing")"

run_check "$repo/CLAUDE.md" "$precious"
assert_eq "check_link fails on a real file at the target" "1" "$CHECK_FAILED"
assert_eq "... and says it is not a symlink" "y" "$(mentions "$check_out" "not a symlink")"

run_check "$repo/CLAUDE.md" "$wrong"
assert_eq "check_link fails on a link to the wrong source" "1" "$CHECK_FAILED"
assert_eq "... and names the source it found instead" "y" "$(mentions "$check_out" "$repo/other.md")"

assert_eq "check_link changes nothing" "$before" "$(snapshot "$home")"

printf '\n'
assert_summary "managed-link"
