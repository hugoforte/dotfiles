#!/bin/sh

# The assertion helper the sh suites share. Deliberately tiny: an equality
# assert, a counter, and a summary. Anything more is a framework, and the
# decision on record is that this repo does not take a test-framework
# dependency (no bats) for a handful of fixture suites.
#
# Usage, from a tests/*.test.sh file:
#
#     . "$SCRIPT_DIR/assert.sh"
#     assert_eq "what this proves" "$expected" "$actual"
#     assert_summary "suite name"   # returns 1 if anything failed
#
# The counters are plain shell variables in the sourcing shell, so every test
# file is its own process with its own tally and its own exit status.

assert_passed=0
assert_failed=0

# assert_eq <name> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then
        assert_passed=$((assert_passed + 1))
        printf '  PASS  %s\n' "$1"
    else
        assert_failed=$((assert_failed + 1))
        printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
    fi
}

# assert_summary <suite name>: print the tally, return 1 if anything failed.
assert_summary() {
    printf '%s: %d passed, %d failed\n' "$1" "$assert_passed" "$assert_failed"
    [ "$assert_failed" -eq 0 ]
}
