#!/bin/sh

# Suite for nextTitle in ai/skills/hf-t3-handoff/t3.mjs, the one part of the
# T3 handoff that is a function of its argument. Everything else in that
# script talks to a running T3 Code server and is not run here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

module="$REPO_ROOT/ai/skills/hf-t3-handoff/t3.mjs"

next_title() {
    # Both go through the environment: with no argv[1] the module only exports.
    T3_MODULE="$module" T3_TITLE="$1" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { nextTitle } = await import(pathToFileURL(process.env.T3_MODULE).href);
        console.log(nextTitle(process.env.T3_TITLE));
    "
}

assert_eq "an unnumbered title gains a 2" "RIG - Automate Handoff 2" "$(next_title 'RIG - Automate Handoff')"
assert_eq "a numbered title counts up" "RIG - Automate Handoff 3" "$(next_title 'RIG - Automate Handoff 2')"
assert_eq "the count passes 9" "Fix flaky test 10" "$(next_title 'Fix flaky test 9')"
assert_eq "a number inside the title is left alone" "Upgrade to v2 docs 2" "$(next_title 'Upgrade to v2 docs')"
assert_eq "surrounding whitespace is dropped" "Tidy 2" "$(next_title '  Tidy  ')"

assert_summary "t3-handoff"
