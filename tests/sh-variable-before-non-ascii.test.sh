#!/bin/sh

# macOS's /bin/sh is bash 3.2, which reads the bytes of a non-ASCII character
# straight after a variable name as part of the name: $REPO followed by an
# ellipsis expands an unset variable and prints the rest of the ellipsis as
# mojibake. Braced, as ${REPO}, it is read right, so the scripts brace a name
# that a non-ASCII character follows.
#
# Only our scripts: the vendored skills under ai/skills are left alone.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

echo "sh scripts brace a variable that a non-ASCII character follows"

found="$(cd "$REPO_ROOT" && git ls-files '*.sh' ':!:ai/skills/**' 'ai/skills/hf-*/**.sh' \
    | LC_ALL=C xargs grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^[:alnum:][:punct:][:space:]]')"
assert_eq "no script has \$NAME directly before a non-ASCII character" "" "$found"

# The failure itself, on the shell running this suite.
value=x
assert_eq "\${NAME}… expands the variable" "x…" "${value}…"

assert_summary "sh-variable-before-non-ascii"
