#!/bin/sh

# Fails when what this public repo is about to publish holds something private: its tracked files,
# and with --pr a pull request's title, body and commit messages, which are public too. Run by
# check.yml on every pull request, and by hand through bin/leak-check before a push.
#
#   sh ai/helpers/leak-check.sh             the tracked files
#   sh ai/helpers/leak-check.sh --pr <n>    and pull request <n>'s text, read with gh
#   sh ai/helpers/leak-check.sh --terms     print the merged private terms, for gh secret set
#
# Two kinds of rule. The generic ones live here: an email address outside the domains kept for
# examples and tests, a private key, a token, a real SSH public key. The private terms never do:
# case-insensitive regular expressions, one per line, from LEAK_CHECK_TERMS when it is set (the CI
# secret), else from every overlay's leak-check/terms.txt. With neither, as on a fork, the generic
# rules run alone. A finding names where and which rule, never the text it matched, so a CI log
# shows no term and no address.

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

. "$REPO/ai/helpers/output.sh"
. "$REPO/ai/helpers/overlays.sh"

usage() { die "usage: $0 [--pr <number> | --terms]"; }

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

if [ -n "${LEAK_CHECK_TERMS:-}" ]; then
    printf '%s\n' "$LEAK_CHECK_TERMS" > "$work/raw"
else
    overlays_load "$REPO" || exit 1
    term_files="$(overlay_sources leak-check/terms.txt)" || exit 1
    : > "$work/raw"
    while IFS= read -r file; do
        [ -z "$file" ] || { cat "$file"; echo; } >> "$work/raw"
    done <<EOF
$term_files
EOF
fi
tr -d '\r' < "$work/raw" | grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*#' > "$work/terms"

if [ "$PRINT_TERMS" = "true" ]; then
    cat "$work/terms"
    exit 0
fi
[ -s "$work/terms" ] || info "No private terms supplied (LEAK_CHECK_TERMS, or an overlay's leak-check/terms.txt): generic rules only"

if [ -n "$PR" ]; then
    gh pr view "$PR" --json title,body,commits \
        --jq '.title, .body, (.commits[] | .messageHeadline, .messageBody)' > "$work/pr" ||
        die "could not read pull request $PR with gh"
fi

# --- the rules -----------------------------------------------------------------------------------

EMAIL='[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}'
PRIVATE_KEY='-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----'
TOKEN='(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|xox[bp]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})'
SSH_KEY='ssh-(ed25519|rsa|ecdsa-[a-z0-9-]+) AAAA[0-9A-Za-z+/]{40,}'

# hits <grep option...>: each match in the tracked files, and with --pr in the pull request's text,
# as <where>:<line>:<text>, the pull request's <where> being "pull request <n>".
hits() {
    git -C "$REPO" grep -n -I "$@" -- .
    [ -z "$PR" ] || grep -n "$@" "$work/pr" | sed "s/^/pull request $PR:/"
}

# where <rule>: each hit's <where>:<line>, then the rule, and nothing of what matched.
where() { cut -d: -f1,2 | sed "s/\$/: $1/"; }

# An address is fine in a domain kept for examples and tests (RFC 2606), from a noreply sender, or
# as the git@host of an SSH remote.
allowed_email() {
    awk '{ m = tolower($0); sub(/^[^:]*:[^:]*:/, "", m)
           if (m ~ /^(noreply|git)@/ || m ~ /@users\.noreply\.github\.com$/ ||
               m ~ /@([a-z0-9-]+\.)*example\.(com|org|net)$/ || m ~ /\.(test|example|invalid|localhost)$/) next
           print }'
}

{
    [ ! -s "$work/terms" ] || hits -i -E -f "$work/terms" | where "a private term"
    hits -o -E -e "$EMAIL" | allowed_email | where "an email address"
    hits -E -e "$PRIVATE_KEY" | where "a private key"
    hits -E -e "$TOKEN" | where "a token"
    hits -E -e "$SSH_KEY" | where "an SSH public key"
} | sort -u > "$work/found"

if [ -s "$work/found" ]; then
    while IFS= read -r finding; do error "$finding"; done < "$work/found"
    die "$(wc -l < "$work/found" | tr -d ' ') finding(s); what matched is not shown. Remove it, or for a private term see README, \"Leak check\""
fi
success "No leaks found"
