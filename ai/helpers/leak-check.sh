#!/bin/sh

# Fails when what a public repo is about to publish holds something private: the tracked files of
# the checkout it runs in, and with --pr a pull request's title, body, commit messages and commit
# authors, which are public too. Run by .github/workflows/leak-check.yml on every pull request and
# every edit to one, and by hand through bin/leak-check before a push.
#
#   leak-check             the checkout you are in
#   leak-check --pr <n>    and pull request <n>, read with gh
#   leak-check --terms     print the overlays' merged private terms, for gh secret set
#
# Two kinds of rule. The generic ones live here: an email address outside the domains kept for
# examples and tests, a private key, a token, a real SSH public key, a UTF-16 file this cannot
# read. The private terms never do: case-insensitive regular expressions, one per line, from
# LEAK_CHECK_TERMS when it is set (the CI secret), else from every overlay's leak-check/terms.txt
# that this dotfiles checkout lists. With neither, as on a fork, the generic rules run alone, unless
# LEAK_CHECK_REQUIRE_TERMS is true. A finding names where and which rule, never the text it
# matched, and a term this cannot use is named by its line: a CI log shows no term and no address.

DOTFILES="$(cd "$(dirname "$0")/../.." && pwd)"

. "$DOTFILES/ai/helpers/output.sh"
. "$DOTFILES/ai/helpers/overlays.sh"

usage() { die "usage: leak-check [--pr <number> | --terms]"; }

PR=""
PRINT_TERMS=false
case "${1:-}" in
    '')      ;;
    --pr)    [ -n "${2:-}" ] || usage; PR="$2" ;;
    --terms) PRINT_TERMS=true ;;
    *)       usage ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

# --- the private terms -------------------------------------------------------------------------

# overlay_terms: every overlay's leak-check/terms.txt, one after another.
overlay_terms() {
    overlays_load "$DOTFILES" || exit 1
    term_files="$(overlay_sources leak-check/terms.txt)" || exit 1
    while IFS= read -r file; do
        [ -z "$file" ] || { cat "$file"; echo; }
    done <<EOF
$term_files
EOF
}

# The terms, one a line: no carriage returns or trailing blanks, no blank or # lines.
clean_terms() { tr -d '\r' | sed 's/[[:space:]]*$//' | grep -v -e '^$' -e '^[[:space:]]*#'; }

if [ "$PRINT_TERMS" = "true" ]; then
    # Always the overlays: a refresh must not push LEAK_CHECK_TERMS, the old secret, back.
    overlay_terms > "$work/raw"
    clean_terms < "$work/raw" > "$work/terms"
    [ -s "$work/terms" ] || die "no overlay this checkout lists ships leak-check/terms.txt; not printing an empty list"
    cat "$work/terms"
    exit 0
fi

if [ -n "${LEAK_CHECK_TERMS:-}" ]; then
    printf '%s\n' "$LEAK_CHECK_TERMS" > "$work/raw"
else
    overlay_terms > "$work/raw"
fi
clean_terms < "$work/raw" > "$work/terms"

# Each term checked alone, so a bad one is named by its line and never echoed: grep prints a
# pattern it cannot compile, and one that matches an empty line matches every line.
n=0
bad=0
while IFS= read -r term; do
    n=$((n + 1))
    echo | grep -E -e "$term" > /dev/null 2>&1
    case $? in
        0) error "term $n matches every line"; bad=1 ;;
        1) ;;
        *) error "term $n is not a valid extended regular expression"; bad=1 ;;
    esac
done < "$work/terms"
[ "$bad" = "0" ] || die "the private terms cannot be used as they are; fix the lines named above"

if [ ! -s "$work/terms" ]; then
    [ "${LEAK_CHECK_REQUIRE_TERMS:-}" != "true" ] ||
        die "no private terms: LEAK_CHECK_TERMS is empty, and this check requires them"
    info "No private terms supplied (LEAK_CHECK_TERMS, or an overlay's leak-check/terms.txt): generic rules only"
fi

# --- what is checked ----------------------------------------------------------------------------

TARGET="$(git rev-parse --show-toplevel 2> /dev/null)" ||
    die "not inside a git checkout: run leak-check from the checkout to check"

if [ -n "$PR" ]; then
    mkdir "$work/pr"
    { gh pr view "$PR" --json title --jq .title > "$work/pr/title" &&
      gh pr view "$PR" --json body --jq .body > "$work/pr/body" &&
      gh pr view "$PR" --json commits --jq '.commits[] | .messageHeadline, .messageBody, ""' > "$work/pr/commits" &&
      gh pr view "$PR" --json commits --jq '.commits[].authors[].email' > "$work/pr/authors"; } 2> /dev/null ||
        die "could not read pull request $PR with gh"
fi

# --- the rules -----------------------------------------------------------------------------------

EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
PRIVATE_KEY='-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----|PuTTY-User-Key-File-[0-9]'
TOKEN='(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|xapp-[A-Za-z0-9-]{10,}|(AKIA|ASIA)[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|tskey-[a-z]+-[A-Za-z0-9-]{10,}|AGE-SECRET-KEY-1[0-9A-Z]{50,})'
SSH_KEY='(ssh-(ed25519|rsa|dss)|ecdsa-sha2-[a-z0-9]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) AAAA[0-9A-Za-z+/]{40,}'

# hits <grep option...>: each match in the tracked files, and with --pr in the pull request's
# title, body and commit messages, as <where>:<line>:<text>, a part's <where> being
# "pull request <n> <part>". A grep that fails, rather than finds nothing, stops the check; its
# message is dropped, since it may quote the pattern.
hits() {
    git -C "$TARGET" grep -n -I "$@" -- . > "$work/hits" 2> /dev/null
    [ $? -le 1 ] || die "git grep failed in $TARGET"
    if [ -n "$PR" ]; then
        for part in title body commits; do
            grep -n "$@" "$work/pr/$part" > "$work/part" 2> /dev/null
            [ $? -le 1 ] || die "grep failed on pull request $PR's $part"
            sed "s/^/pull request $PR $part:/" "$work/part" >> "$work/hits"
        done
    fi
    cat "$work/hits"
}

# where <rule>: each hit's <where>:<line>, then the rule, and nothing of what matched.
where() { cut -d: -f1,2 | sed "s/\$/: $1/"; }

# An address is fine in a domain kept for examples and tests (RFC 2606), from GitHub's or
# Anthropic's noreply senders, as the git@ of a public forge's SSH remote, as an SSH algorithm's
# name, or as an image's @2x.
allowed_email() {
    awk '{ m = tolower($0); sub(/^[^:]*:[^:]*:/, "", m)
           if (m ~ /@([a-z0-9-]+\.)*example\.(com|org|net)$/ || m ~ /\.(test|example|invalid|localhost)$/ ||
               m ~ /^noreply@(github|anthropic)\.com$/ || m ~ /@users\.noreply\.github\.com$/ ||
               m ~ /^git@(github\.com|gitlab\.com|bitbucket\.org)$/ || m ~ /@openssh\.com$/ ||
               m ~ /@[0-9]+x\.(png|jpe?g|gif|svg|webp)$/) next
           print }'
}

# utf16_files: the tracked files that begin with a UTF-16 byte-order mark, which no grep here reads
# as the text it shows. Only those git does not already read as text are opened.
utf16_files() {
    git -C "$TARGET" ls-files > "$work/all"
    git -C "$TARGET" grep -I -l -e '' -- . > "$work/text" 2> /dev/null
    grep -vxF -f "$work/text" "$work/all" | while IFS= read -r file; do
        case "$(head -c 2 "$TARGET/$file" 2> /dev/null | od -An -tx1 | tr -d ' \n')" in
            fffe|feff) printf '%s: a UTF-16 file, which this check cannot read\n' "$file" ;;
        esac
    done
}

: > "$work/found"
if [ -s "$work/terms" ]; then
    hits -i -E -f "$work/terms" | where "a private term" >> "$work/found"
    git -C "$TARGET" ls-files | grep -n -i -E -f "$work/terms" | cut -d: -f1 |
        sed 's/^\(.*\)$/git ls-files line \1: a private term in a path/' >> "$work/found"
    if [ -n "$PR" ]; then
        # A term of more than one word may be wrapped onto two lines of a message.
        for part in body commits; do
            tr '\n' ' ' < "$work/pr/$part" | grep -q -i -E -f "$work/terms" &&
                ! grep -q "^pull request $PR $part:" "$work/found" &&
                printf 'pull request %s %s: a private term, across lines\n' "$PR" "$part" >> "$work/found"
        done
        grep -n -i -E -f "$work/terms" "$work/pr/authors" | cut -d: -f1 |
            sed "s/^\(.*\)\$/pull request $PR authors:\1: a private term/" >> "$work/found"
    fi
fi
hits -o -E -e "$EMAIL" | allowed_email | where "an email address" >> "$work/found"
hits -E -e "$PRIVATE_KEY" | where "a private key" >> "$work/found"
hits -E -e "$TOKEN" | where "a token" >> "$work/found"
hits -E -e "$SSH_KEY" | where "an SSH public key" >> "$work/found"
utf16_files >> "$work/found"

sort -u "$work/found" > "$work/report"
if [ -s "$work/report" ]; then
    while IFS= read -r finding; do error "$finding"; done < "$work/report"
    die "$(wc -l < "$work/report" | tr -d ' ') finding(s) in $TARGET; what matched is not shown. Remove it, or see dotfiles' README, \"Leak check\""
fi
success "No leaks found in $TARGET"
