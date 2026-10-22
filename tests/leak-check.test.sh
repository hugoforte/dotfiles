#!/bin/sh

# Fixture suite for ai/helpers/leak-check.sh: it fails a checkout, or a pull request's title, body,
# commit messages and commit authors, that holds a private term or something the generic rules
# catch, names where without ever printing what, refuses terms it cannot use, and runs the generic
# rules alone when no terms are supplied, as on a fork. The private terms are fake, from
# LEAK_CHECK_TERMS or a fixture overlay's leak-check/terms.txt; gh is a stub on PATH.
#
# Everything token-, key- or address-shaped is built at run time, so this file holds none of them
# for the check to find.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
other="$work/other"
overlay="$work/private/personal"
stubs="$work/stubs"
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$repo/docs" "$other" "$overlay/leak-check" "$stubs" "$work/pr"
cp "$REPO_ROOT/ai/helpers/output.sh" "$REPO_ROOT/ai/helpers/overlays.sh" "$REPO_ROOT/ai/helpers/leak-check.sh" "$repo/ai/helpers/"
printf 'ai/secrets/machine.local.psd1\n' > "$repo/.gitignore"
printf '# A clean file\n\nWrite to someone@example.com, or clone git@github.com:owner/repo.git.\n' > "$repo/docs/clean.md"
printf 'ssh-ed25519 AAAA laptop\n' > "$repo/docs/fixture-key.txt"
for dir in "$repo" "$other"; do
    git -C "$dir" init -q
    git -C "$dir" config core.autocrlf false
done
git -C "$repo" add -A

# The pull request gh describes, one file a part. The stub answers only the queries the check
# makes, so a change to what it asks for fails here.
printf 'Clean title\n' > "$work/pr/title"
printf 'A clean body.\n' > "$work/pr/body"
printf 'Add a clean thing\n\n' > "$work/pr/commits"
printf 'someone@example.com\n' > "$work/pr/authors"
cat_part() { printf 'cat "%s/pr/%s"' "$work" "$1"; }
{
    printf '#!/bin/sh\n'
    printf '[ "$1 $2 $3" = "pr view 7" ] || exit 1\n'
    printf 'case "$4 $5 $6 $7" in\n'
    printf '  "--json title --jq .title") %s ;;\n' "$(cat_part title)"
    printf '  "--json body --jq .body") %s ;;\n' "$(cat_part body)"
    printf '  "--json commits --jq .commits[] | .messageHeadline, .messageBody, \\"\\"") %s ;;\n' "$(cat_part commits)"
    printf '  "--json commits --jq .commits[].authors[].email") %s ;;\n' "$(cat_part authors)"
    printf '  *) echo "unexpected gh query: $*" >&2; exit 3 ;;\nesac\n'
} > "$stubs/gh"
chmod +x "$stubs/gh"
PATH="$stubs:$PATH"; export PATH

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
check() { (cd "$repo" && sh "$repo/ai/helpers/leak-check.sh" "$@" 2>&1); }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
add() { printf '%s\n' "$2" >> "$repo/$1"; git -C "$repo" add -A; }
undo() { git -C "$repo" rm -q --cached "$1"; rm -f "$repo/$1"; }
passes() { out="$(check "$@")"; echo $?; }

# Shapes the check looks for, built here so this file holds none.
dotcom=".$(printf 'co')m"
email="jane.doe@corp$dotcom"
x30="$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36)"
b64="$(printf 'C3NzaC1lZDI1NTE5AAAAIBq%.0s' 1 2)"
priv="$(printf 'PRIV')ATE"

unset LEAK_CHECK_TERMS LEAK_CHECK_REQUIRE_TERMS

# --- a clean checkout, and no terms --------------------------------------------------------------

out="$(check)"; rc=$?
assert_eq "a clean checkout with no terms passes" "0" "$rc"
assert_eq "and says only the generic rules ran" "y" "$(says "$out" "generic rules only")"
LEAK_CHECK_REQUIRE_TERMS=true; export LEAK_CHECK_REQUIRE_TERMS
assert_eq "but fails where terms are required, as in CI on this repo's own pull requests" "1" "$(passes)"
unset LEAK_CHECK_REQUIRE_TERMS

# --- private terms from CI -------------------------------------------------------------------------

LEAK_CHECK_TERMS="$(printf 'acme ?corp  \n# a comment\nwidget-co\r\nbig deal inc')"; export LEAK_CHECK_TERMS
add notes.txt "We built this for AcmeCorp last year."
out="$(check)"; rc=$?
assert_eq "a private term from LEAK_CHECK_TERMS fails the checkout" "1" "$rc"
assert_eq "naming the file, the line and the rule, matching without case" "y" "$(says "$out" "notes.txt:1: a private term")"
assert_eq "and never printing the term" "n" "$(says "$(lower "$out")" "acmecorp")"
undo notes.txt
assert_eq "with the term gone the checkout passes" "0" "$(passes)"

add "docs/acmecorp-notes.txt" "clean"
out="$(check)"; rc=$?
assert_eq "a private term in a file's path fails" "1" "$rc"
assert_eq "by its line in git ls-files, not by its path" "y" "$(says "$out" "git ls-files line ")"
assert_eq "so the path is not printed" "n" "$(says "$(lower "$out")" "acmecorp")"
undo "docs/acmecorp-notes.txt"

printf '\377\376' > "$repo/utf16.txt"; printf 'h\000i\000' >> "$repo/utf16.txt"; git -C "$repo" add -A
out="$(check)"; rc=$?
assert_eq "a UTF-16 file, which the check cannot read, fails" "1" "$rc"
assert_eq "and is named for what it is" "y" "$(says "$out" "utf16.txt: a UTF-16 file")"
undo utf16.txt

LEAK_CHECK_TERMS="$(printf 'acme\nunclosed(paren')"
out="$(check)"; rc=$?
assert_eq "a term that is not a valid regular expression fails the check" "1" "$rc"
assert_eq "naming its line in the list" "y" "$(says "$out" "term 2 is not a valid")"
assert_eq "and not the term" "n" "$(says "$out" "unclosed")"
LEAK_CHECK_TERMS="$(printf 'acme\n|')"
out="$(check)"; rc=$?
assert_eq "a term that matches everything fails the check, by its line" "y" "$(says "$out" "term 2 matches every line")"
LEAK_CHECK_TERMS='acme ?corp'

# --- private terms from the overlays ---------------------------------------------------------------

unset LEAK_CHECK_TERMS
printf 'widget-co\n\n' > "$overlay/leak-check/terms.txt"
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$overlay")" > "$repo/ai/secrets/machine.local.psd1"
add notes.txt "Ask Widget-Co."
out="$(check)"; rc=$?
assert_eq "a private term from an overlay's leak-check/terms.txt fails the checkout" "1" "$rc"
assert_eq "and is not printed either" "n" "$(says "$(lower "$out")" "widget-co")"
undo notes.txt
assert_eq "--terms prints the overlays' merged terms, for gh secret set" "widget-co" "$(check --terms)"
LEAK_CHECK_TERMS='stale'; export LEAK_CHECK_TERMS
assert_eq "even with LEAK_CHECK_TERMS set, so a refresh never pushes the old secret back" "widget-co" "$(check --terms)"
unset LEAK_CHECK_TERMS

# The leak-check on PATH lives in one checkout; it checks the one it is run in.
printf 'Ask Widget-Co.\n' > "$other/notes.txt"; git -C "$other" add -A
out="$(cd "$other" && sh "$repo/ai/helpers/leak-check.sh" 2>&1)"; rc=$?
assert_eq "run in another checkout, it checks that checkout" "1" "$rc"
assert_eq "with the terms of the overlays its own checkout lists" "y" "$(says "$out" "notes.txt:1: a private term")"
out="$(cd "$work" && sh "$repo/ai/helpers/leak-check.sh" 2>&1)"; rc=$?
assert_eq "outside any checkout it fails rather than passing on nothing" "1" "$rc"
rm -f "$repo/ai/secrets/machine.local.psd1"
out="$(check --terms)"; rc=$?
assert_eq "--terms with no terms found fails, so the secret is never set empty" "1" "$rc"

# --- the generic rules ------------------------------------------------------------------------------

add notes.txt "Mail $email about it."
out="$(check)"; rc=$?
assert_eq "an email address fails" "1" "$rc"
assert_eq "naming the rule" "y" "$(says "$out" "notes.txt:1: an email address")"
assert_eq "without printing the address" "n" "$(says "$out" "jane.doe")"
undo notes.txt

add notes.txt "Co-Authored-By: A Bot <noreply@github$dotcom>, and 123+someone@users$(printf .noreply).github$dotcom"
assert_eq "a GitHub noreply address passes" "0" "$(passes)"
undo notes.txt
add notes.txt "From noreply@corp$dotcom, or clone git@git$(printf .corp)$dotcom:x/y"
assert_eq "but noreply or git@ at a private host fails" "1" "$(passes)"
undo notes.txt
add notes.txt "Ciphers chacha20-poly1305@openssh$dotcom, logo@2x.png, me@mail.test, you@host.example"
assert_eq "an SSH algorithm name, an image at 2x and a domain kept for testing pass" "0" "$(passes)"
undo notes.txt

for shape in "-----BEGIN OPENSSH $priv KEY-----" "-----BEGIN PGP $priv KEY BLOCK-----" "PuTTY-User-Key-File-$(printf 3): ssh-ed25519"; do
    add key.txt "$shape"
    out="$(check)"
    assert_eq "a private key fails: ${shape%% *}…" "y" "$(says "$out" "key.txt:1: a private key")"
    undo key.txt
done

for token in "ghp_$x30" "github_pat_$x30" "glpat-$x30" "sk-ant-$x30" "AKIA$(printf 'A%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)" \
             "tskey-auth-$x30" "AGE-SECRET-KEY-1$(printf 'Q%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58)"; do
    add token.txt "token=$token"
    out="$(check)"
    assert_eq "a token fails, by its rule: ${token%%[0-9A-Z]*}…" "y" "$(says "$out" "token.txt:1: a token")"
    undo token.txt
done

for key in "ssh-ed25519 AAAA$b64" "ecdsa-sha2-nistp256 AAAA$b64" "sk-ssh-ed25519@openssh$dotcom AAAA$b64"; do
    add authorized_keys "$key me@laptop"
    out="$(check)"
    assert_eq "a real SSH public key fails: ${key%% *}" "y" "$(says "$out" "authorized_keys:1: an SSH public key")"
    undo authorized_keys
done

printf 'not tracked: %s\n' "$email" > "$repo/untracked.txt"
assert_eq "a file git does not track is not this check's" "0" "$(passes)"
rm -f "$repo/untracked.txt"

# --- a pull request's text --------------------------------------------------------------------------

assert_eq "a clean pull request passes" "0" "$(passes --pr 7)"

LEAK_CHECK_TERMS="$(printf 'acme ?corp\nbig deal inc')"; export LEAK_CHECK_TERMS
printf 'Built for Acme Corp\n' > "$work/pr/title"
out="$(check --pr 7)"; rc=$?
assert_eq "a private term in a pull request's title fails" "1" "$rc"
assert_eq "naming the pull request and the part" "y" "$(says "$out" "pull request 7 title:1: a private term")"
assert_eq "and not the term" "n" "$(says "$(lower "$out")" "acme corp")"
printf 'Clean title\n' > "$work/pr/title"

printf 'Add a thing\n\nWe built it\nfor Big\nDeal Inc in a week.\n\n' > "$work/pr/commits"
out="$(check --pr 7)"; rc=$?
assert_eq "a term wrapped across lines of a commit message fails" "1" "$rc"
assert_eq "named as found across lines" "y" "$(says "$out" "pull request 7 commits: a private term, across lines")"
printf 'Add a clean thing\n\n' > "$work/pr/commits"

printf 'dev@acmecorp.example\n' > "$work/pr/authors"
out="$(check --pr 7)"; rc=$?
assert_eq "a private term in a commit author's address fails" "1" "$rc"
assert_eq "named as an author" "y" "$(says "$out" "pull request 7 authors:1: a private term")"
printf 'someone@example.com\n' > "$work/pr/authors"
unset LEAK_CHECK_TERMS

printf 'Fix it\n\nReported by %s\n\n' "$email" > "$work/pr/commits"
out="$(check --pr 7)"; rc=$?
assert_eq "an email address in a commit message fails" "1" "$rc"
printf 'Add a clean thing\n\n' > "$work/pr/commits"

assert_eq "a pull request gh cannot read fails the check" "1" "$(passes --pr 8)"

assert_summary "leak-check"
