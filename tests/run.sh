#!/bin/sh

# Runs every tests/*.test.sh and exits non-zero if any of them failed.
# This is the CI entry point for the sh half of the suite, and it is the same
# command locally: `sh tests/run.sh`, from any working directory.
#
# Each test file is run in its own `sh` process, so one file crashing or
# calling `exit` cannot take the rest of the run with it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/../ai/helpers/output.sh"

files=0
failures=0

for test_file in "$SCRIPT_DIR"/*.test.sh; do
    [ -f "$test_file" ] || continue
    files=$((files + 1))
    test_name="$(basename "$test_file")"
    printf '=== %s ===\n' "$test_name"
    if sh "$test_file"; then
        success "$test_name"
    else
        failures=$((failures + 1))
        error "$test_name"
    fi
    printf '\n'
done

if [ "$files" -eq 0 ]; then
    error "No test files found in $SCRIPT_DIR"
    exit 1
fi

printf '======== %d test files, %d failed ========\n' "$files" "$failures"
[ "$failures" -eq 0 ]
