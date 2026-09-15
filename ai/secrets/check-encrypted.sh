#!/bin/sh
# Fails if any file under ai/secrets/ that should be encrypted lacks SOPS metadata.
# Run before committing; ai/install.sh --check runs it too.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
status=0
for f in "$SCRIPT_DIR"/*/*; do
    [ -f "$f" ] || continue
    if ! grep -qE 'sops_|"sops"' "$f"; then
        echo "NOT ENCRYPTED: $f" >&2
        status=1
    fi
done
exit $status
