#!/bin/sh
# Fails if any file under a secrets directory that should be encrypted lacks SOPS metadata.
# Audits the directory given as $1, or this script's own directory (ai/secrets/) by default.
# Run before committing; ai/install.sh --check runs it for this repo and each overlay.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/../.." && pwd)"
SECRETS_DIR="${1:-$SCRIPT_DIR}"

. "$ZSH/ai/helpers/output.sh"

status=0
# Both patterns are needed: a POSIX glob never matches dot-prefixed names, and the
# secret files are mostly called .secrets.env. `.` and `..` fall out at the -f test.
for f in "$SECRETS_DIR"/*/* "$SECRETS_DIR"/*/.*; do
    [ -f "$f" ] || continue
    if ! grep -qE 'sops_|"sops"' "$f"; then
        error "NOT ENCRYPTED: $f"
        status=1
    fi
done
exit $status
