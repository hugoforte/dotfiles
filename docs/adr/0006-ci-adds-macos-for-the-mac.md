# CI runs windows-latest and macos-latest, and nothing else

Supersedes [0004](0004-ci-runs-windows-only.md).

`.github/workflows/check.yml` has two jobs: the Windows one 0004 describes, unchanged, and a
`macos-latest` job that runs the shell syntax check and `sh tests/run.sh` under `/bin/sh`.

0004 kept CI on one OS because this repo configured Windows machines and nothing else, so a run
on any other OS could only pass vacuously. That stopped being true when the `macos/` entry point
arrived: a Mac now runs `ai/install.sh`, `macos/` and `bin/` for real, with plain `ln -s` where
Windows has `MSYS=winsymlinks:nativestrict`, BSD `sed`, `date` and `readlink` where Windows has
GNU, and `/bin/sh` where Windows has Git Bash. A defect in any of those is invisible on the
Windows runner, which is 0004's own argument pointing the other way.

0004's argument against a green check that cannot fail still holds, and it shapes the job:

- **The macOS job runs the sh half only.** The PowerShell scripts configure Windows; Pester on
  a Mac would pass tests of behaviour no Mac has.
- **The Windows job stays the evidence for Windows.** The two defects 0004 names pass vacuously
  on a Mac, so the Windows job keeps `shell: powershell` (5.1) and Git Bash exactly as it was.
- **No Linux job.** No machine this repo configures runs Linux, so a Linux runner would still
  be coverage of nothing.

A sh test that only means something on one OS says so and skips itself elsewhere, rather than
passing.
