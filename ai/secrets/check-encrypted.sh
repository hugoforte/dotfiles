#!/bin/sh
# Fails if any file under ai/secrets/ that should be encrypted lacks SOPS metadata.
# Run before committing; ai/install.sh --check runs it too.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/../.." && pwd)"

. "$ZSH/ai/helpers/output.sh"

status=0
# Both patterns are needed: a POSIX glob never matches dot-prefixed names, and the
# secret files are mostly called .secrets.env. `.` and `..` fall out at the -f test.
for f in "$SCRIPT_DIR"/*/* "$SCRIPT_DIR"/*/.*; do
    [ -f "$f" ] || continue
    if ! grep -qE 'sops_|"sops"' "$f"; then
        error "NOT ENCRYPTED: $f"
        status=1
    fi
done
exit $status
