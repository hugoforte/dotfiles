#!/bin/sh

# Fixture suite for ai/helpers/leak-check.sh: it fails a tree, or a pull request's title, body and
# commit messages, that holds a private term or something the generic rules catch, names where
# without ever printing what, and runs the generic rules alone when no terms are supplied, as on a
# fork. The private terms are fake, from LEAK_CHECK_TERMS or a fixture overlay's
# leak-check/terms.txt; gh is a stub on PATH.
#
# The token-shaped strings are built at run time, so this file holds none for the check to find.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
overlay="$work/private/personal"
stubs="$work/stubs"
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$repo/docs" "$overlay/leak-check" "$stubs"
cp "$REPO_ROOT/ai/helpers/output.sh" "$REPO_ROOT/ai/helpers/overlays.sh" "$REPO_ROOT/ai/helpers/leak-check.sh" "$repo/ai/helpers/"
printf 'ai/secrets/machine.local.psd1\n' > "$repo/.gitignore"
printf '# A clean file\n\nWrite to someone@example.com, or clone git@github.com:owner/repo.git.\n' > "$repo/docs/clean.md"
printf 'ssh-ed25519 AAAA laptop\n' > "$repo/docs/fixture-key.txt"
git -C "$repo" init -q
git -C "$repo" config core.autocrlf false
git -C "$repo" add -A

# The pull request gh describes: its title, body and commit messages, from files the tests write.
printf 'Clean title\n' > "$work/title"
printf 'A clean body.\n' > "$work/body"
printf 'Add a clean thing\n' > "$work/commit"
printf '#!/bin/sh\ncase "$*" in\n  *"pr view"*) printf "%%s\\n" "$(cat "%s")" "$(cat "%s")" "$(cat "%s")" ;;\n  *) exit 1 ;;\nesac\n' \
    "$work/title" "$work/body" "$work/commit" > "$stubs/gh"
chmod +x "$stubs/gh"
PATH="$stubs:$PATH"; export PATH

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
check() { (cd "$work" && sh "$repo/ai/helpers/leak-check.sh" "$@" 2>&1); }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
add() { printf '%s\n' "$2" >> "$repo/$1"; git -C "$repo" add -A; }
undo() { git -C "$repo" rm -q --cached "$1"; rm -f "$repo/$1"; }

unset LEAK_CHECK_TERMS

# --- a clean tree, and no terms --------------------------------------------------------------------

out="$(check)"; rc=$?
assert_eq "a clean tree with no terms passes" "0" "$rc"
assert_eq "and says only the generic rules ran" "y" "$(says "$out" "generic rules only")"

# --- private terms from CI ---------------------------------------------------------------------------

LEAK_CHECK_TERMS="$(printf 'acme ?corp\nwidget-co')"; export LEAK_CHECK_TERMS
add notes.txt "We built this for AcmeCorp last year."
out="$(check)"; rc=$?
assert_eq "a private term from LEAK_CHECK_TERMS fails the tree" "1" "$rc"
assert_eq "naming the file and line" "y" "$(says "$out" "notes.txt:1")"
assert_eq "matching without case, as a regular expression" "y" "$(says "$out" "private term")"
assert_eq "and never printing the term" "n" "$(says "$(printf '%s' "$out" | tr 'A-Z' 'a-z')" "acmecorp")"
undo notes.txt
out="$(check)"; rc=$?
assert_eq "with the term gone the tree passes" "0" "$rc"
unset LEAK_CHECK_TERMS

# --- private terms from the overlays ---------------------------------------------------------------

printf 'widget-co\n\n' > "$overlay/leak-check/terms.txt"
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$overlay")" > "$repo/ai/secrets/machine.local.psd1"
add notes.txt "Ask Widget-Co."
out="$(check)"; rc=$?
assert_eq "a private term from an overlay's leak-check/terms.txt fails the tree" "1" "$rc"
assert_eq "and is not printed either" "n" "$(says "$(printf '%s' "$out" | tr 'A-Z' 'a-z')" "widget-co")"
undo notes.txt
out="$(check --terms)"
assert_eq "--terms prints the merged terms, for gh secret set" "widget-co" "$out"
rm -f "$repo/ai/secrets/machine.local.psd1"

# --- the generic rules ------------------------------------------------------------------------------

email="jane.doe@corp.$(printf 'co')m"
add notes.txt "Mail $email about it."
out="$(check)"; rc=$?
assert_eq "an email address fails" "1" "$rc"
assert_eq "naming the rule" "y" "$(says "$out" "notes.txt:1: an email address")"
assert_eq "without printing the address" "n" "$(says "$out" "jane.doe")"
undo notes.txt

add notes.txt "Co-Authored-By: A Bot <noreply@bots.example>, and 123+someone@users.noreply.github.com"
out="$(check)"; rc=$?
assert_eq "a noreply address passes" "0" "$rc"
undo notes.txt

add notes.txt "Write to me@mail.test, you@host.example or them@dev.localhost."
out="$(check)"; rc=$?
assert_eq "an address in a domain kept for testing passes" "0" "$rc"
undo notes.txt

add key.txt "-----BEGIN OPENSSH $(printf 'PRIV')ATE KEY-----"
out="$(check)"; rc=$?
assert_eq "a private key fails" "1" "$rc"
assert_eq "naming the rule" "y" "$(says "$out" "key.txt:1: a private key")"
undo key.txt

token="ghp_$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)"
add token.txt "token=$token"
out="$(check)"; rc=$?
assert_eq "a token fails" "1" "$rc"
assert_eq "naming the rule, not the token" "y" "$(says "$out" "token.txt:1: a token")"
undo token.txt

key="ssh-ed25519 AAAA$(printf 'C3NzaC1lZDI1NTE5AAAAIBq%.0s' 1 2)"
add authorized_keys "$key me@laptop"
out="$(check)"; rc=$?
assert_eq "a real SSH public key fails" "1" "$rc"
assert_eq "naming the rule" "y" "$(says "$out" "authorized_keys:1: an SSH public key")"
undo authorized_keys

printf 'not tracked: %s\n' "$email" > "$repo/untracked.txt"
out="$(check)"; rc=$?
assert_eq "a file git does not track is not this check's" "0" "$rc"
rm -f "$repo/untracked.txt"

# --- a pull request's text --------------------------------------------------------------------------

out="$(check --pr 7)"; rc=$?
assert_eq "a clean pull request passes" "0" "$rc"

LEAK_CHECK_TERMS='acme ?corp'; export LEAK_CHECK_TERMS
printf 'Built for Acme Corp\n' > "$work/body"
out="$(check --pr 7)"; rc=$?
assert_eq "a private term in a pull request's body fails" "1" "$rc"
assert_eq "naming the pull request" "y" "$(says "$out" "pull request 7")"
assert_eq "and not the term" "n" "$(says "$(printf '%s' "$out" | tr 'A-Z' 'a-z')" "acme corp")"
printf 'A clean body.\n' > "$work/body"
unset LEAK_CHECK_TERMS

printf 'Fix it\n\nReported by %s\n' "$email" > "$work/commit"
out="$(check --pr 7)"; rc=$?
assert_eq "an email address in a commit message fails" "1" "$rc"

assert_summary "leak-check"
