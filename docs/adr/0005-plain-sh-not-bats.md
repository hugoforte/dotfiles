# The shell tests use plain POSIX sh, not bats

`tests/*.test.sh` share a 35-line `assert.sh` instead of a test framework. `bats` is the
better-known tool and the honest argument for it is real: setup and teardown hooks, tagging, TAP
output, and no hand-rolled assertion helper to maintain.

It was rejected on two counts specific to this repo. It would need an entry in
`powershell/tools.psd1` and an install on every machine, for a suite of about thirty assertions
that are all "did this equal that". And bats-on-Git-Bash is a known source of friction on exactly
the platform this repo targets and CI runs — see [0004](0004-ci-runs-windows-only.md).

This is the cheapest of the decisions here to reverse, and it is recorded only so the next person
to suggest `bats` can see it was considered rather than missed. If the suite outgrows a helper —
real fixtures, tagging, parallelism — `bats` is the upgrade path.
