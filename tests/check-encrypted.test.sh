#!/bin/sh

# Fixture suite for ai/secrets/check-encrypted.sh, the dot-glob audit.
#
# The script derives SCRIPT_DIR from its own location, so a copy of it placed
# in a fake repo tree audits that tree and nothing else. Every file this suite
# touches lives in a temp directory it creates and removes; the real
# ai/secrets/ is only ever read.
#
# What is under test is the glob: a POSIX glob never matches dot-prefixed
# names, and the secret files are mostly called .secrets.env, so `*/*` alone
# walks straight past a plaintext one.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

secrets="$work/ai/secrets"
mkdir -p "$secrets/skillA" "$secrets/skillB" "$work/ai/helpers"

cp "$REPO_ROOT/ai/helpers/output.sh" "$work/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/secrets/check-encrypted.sh" "$secrets/check-encrypted.sh"

# A properly encrypted file (it carries SOPS metadata), dot-prefixed: the
# real-world shape, and the one the audit must stay quiet about.
printf '{"data":"x","sops":{"age":[]}}\n' > "$secrets/skillA/.secrets.env"
# A PLAINTEXT dot-prefixed file. This is the one that must be caught.
printf 'API_KEY=hunter2\n' > "$secrets/skillB/.secrets.env"
# A plaintext non-dot file: the control, caught by either glob.
printf 'API_KEY=hunter2\n' > "$secrets/skillB/plain.env"

# The same script with the dot glob taken back out, to prove the fixture can
# tell the two globs apart. If the loop is ever rewritten this substitution
# stops matching, and the guard assertion below goes red rather than silently
# testing two identical scripts.
old_glob="$secrets/old-glob-check.sh"
sed 's|^for f in .*$|for f in "$SCRIPT_DIR"/*/*; do|' "$secrets/check-encrypted.sh" > "$old_glob"
if [ "$(cat "$secrets/check-encrypted.sh")" = "$(cat "$old_glob")" ]; then
    differs=n
else
    differs=y
fi
assert_eq "old-glob variant really differs from the shipped script" "y" "$differs"

printf '=== the shipped glob ===\n'
new_out="$(sh "$secrets/check-encrypted.sh" 2>&1)"; new_rc=$?
printf '%s\n' "$new_out" | sed 's/^/        /'
assert_eq "audit fails when a plaintext secret is present" "1" "$new_rc"
case "$new_out" in *"skillB/.secrets.env"*) caught=y ;; *) caught=n ;; esac
assert_eq "catches the plaintext dot-prefixed secret" "y" "$caught"
case "$new_out" in *"skillB/plain.env"*) control=y ;; *) control=n ;; esac
assert_eq "catches the plaintext non-dot control" "y" "$control"
case "$new_out" in *"skillA/.secrets.env"*) noisy=y ;; *) noisy=n ;; esac
assert_eq "stays quiet about the encrypted dot-prefixed file" "n" "$noisy"

printf '=== the old glob, for contrast ===\n'
# The variant sits beside the real one, so it derives the same SCRIPT_DIR.
old_out="$(sh "$old_glob" 2>&1)"
printf '%s\n' "$old_out" | sed 's/^/        /'
case "$old_out" in *"skillB/.secrets.env"*) old_caught=y ;; *) old_caught=n ;; esac
assert_eq "old glob walks past the plaintext dot-prefixed secret" "n" "$old_caught"
case "$old_out" in *"skillB/plain.env"*) old_control=y ;; *) old_control=n ;; esac
assert_eq "old glob still sees the non-dot control" "y" "$old_control"

printf '=== dot entries ===\n'
# Shells differ on whether `.*` yields `.` and `..` at all; either way neither
# may survive the -f test and reach grep.
leaked=""
for f in "$secrets"/*/* "$secrets"/*/.*; do
    case "${f##*/}" in
        .|..) [ -f "$f" ] && leaked="$leaked $f" ;;
    esac
done
assert_eq "'.' and '..' never pass the -f test" "" "$leaked"

printf '=== a directory argument ===\n'
# An overlay's secrets live outside this tree; the argument points the audit
# there and only there.
overlay="$work/overlay"
mkdir -p "$overlay/ai/secrets/skillC"
printf 'API_KEY=hunter2\n' > "$overlay/ai/secrets/skillC/.secrets.env"
arg_out="$(sh "$secrets/check-encrypted.sh" "$overlay/ai/secrets" 2>&1)"; arg_rc=$?
printf '%s\n' "$arg_out" | sed 's/^/        /'
assert_eq "audit of another directory fails on its plaintext secret" "1" "$arg_rc"
case "$arg_out" in *"skillC/.secrets.env"*) arg_caught=y ;; *) arg_caught=n ;; esac
assert_eq "names the plaintext secret in that directory" "y" "$arg_caught"
case "$arg_out" in *"skillB"*) arg_own=y ;; *) arg_own=n ;; esac
assert_eq "leaves its own directory out of it" "n" "$arg_own"

printf '=== ai/install.sh --check audits each overlay ===\n'
# install.sh derives ZSH from its own location and the home directories from
# $HOME, so a repo tree whose own secrets are clean, with $HOME inside the temp
# directory, isolates the overlay audit.
case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac
repo="$work/repo"
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$repo/ai/skills/kept" "$work/home"
cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
cp "$REPO_ROOT/ai/secrets/check-encrypted.sh" "$repo/ai/secrets/check-encrypted.sh"
printf -- '---\nname: kept\n---\n' > "$repo/ai/skills/kept/SKILL.md"
HOME="$work/home"; export HOME
sh "$repo/ai/install.sh" --skills-only > /dev/null 2>&1

# Written the way a Windows machine writes it, drive letter and backslashes,
# where cygpath can say what that is.
overlay_path="$overlay"
command -v cygpath > /dev/null 2>&1 && overlay_path="$(cygpath -w "$overlay")"
printf "@{\n    SearchRoots = @('C:\\\\source')\n    Overlays = @(\n        '%s'\n    )\n}\n" "$overlay_path" \
    > "$repo/ai/secrets/machine.local.psd1"

check_out="$(sh "$repo/ai/install.sh" --check --skills-only 2>&1)"; check_rc=$?
printf '%s\n' "$check_out" | sed 's/^/        /'
assert_eq "check fails on a plaintext secret in a listed overlay" "1" "$check_rc"
case "$check_out" in *"skillC/.secrets.env"*) check_caught=y ;; *) check_caught=n ;; esac
assert_eq "check names the overlay's plaintext secret" "y" "$check_caught"

printf '{"data":"x","sops":{"age":[]}}\n' > "$overlay/ai/secrets/skillC/.secrets.env"
sh "$repo/ai/install.sh" --check --skills-only > /dev/null 2>&1; clean_rc=$?
assert_eq "check passes once the overlay's secret is encrypted" "0" "$clean_rc"

printf "@{ Overlays = @('%s') }\n" "$work/no-such-overlay" > "$repo/ai/secrets/machine.local.psd1"
missing_out="$(sh "$repo/ai/install.sh" --check --skills-only 2>&1)"; missing_rc=$?
assert_eq "check fails when a listed overlay does not exist" "1" "$missing_rc"
case "$missing_out" in *"no-such-overlay"*) missing_named=y ;; *) missing_named=n ;; esac
assert_eq "check names the missing overlay" "y" "$missing_named"

printf '\n'
assert_summary "check-encrypted"
