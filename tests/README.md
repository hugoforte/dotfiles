# Tests

Fixture tests for the parts of this repo that can be tested without touching the machine you
are on. CI runs all of it on every pull request (`.github/workflows/check.yml`).

## Running them

```sh
sh tests/run.sh                      # the POSIX sh suite
```

```powershell
.\tests\Run-Pester.ps1               # the PowerShell suite (needs Pester 5)
```

Both are runnable from any directory and both exit non-zero when something fails. Neither
reads or writes `~/.claude`, `$HOME` or `%USERPROFILE%`.

If `Run-Pester.ps1` says Pester 5 is missing:

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
```

It will not install it for you. Nothing in this repo installs something behind your back.

## What is covered, and why only this

The interfaces that are functions of their arguments, which is the only reason any of this is
testable yet:

| Under test | Seam | Shipped in |
| --- | --- | --- |
| `ai/helpers/settings-reconcile.sh` | `reconcile_settings <direction> <target> <fragment>` takes both paths | #13 |
| `powershell/output.ps1` | the result object is data, not console text | #14 |
| `ai/secrets/check-encrypted.sh` | a pure function of a directory tree | #12 |
| `powershell/managed-link.ps1` | three verbs, and both paths are arguments | #6 |
| `powershell/git.ps1` | the merge verdict is a function of two refs, and `-Yes` opens the delete | #21 |
| `ai/install.sh`'s `link` / `unlink_if_link` / `check_link` | the same contract in sh, extracted to a fixture rather than run | #6 |
| `ai/skills/hf-t3-handoff/t3.mjs`'s `nextTitle` | exported, and the script only acts when run directly | #14 |

**Everything else is untestable on purpose, not by oversight.** `setup.ps1`, `sync.ps1`,
`install-sync-task.ps1`, and `install-tools.ps1` / `deploy-secrets.ps1` without `-Check` read
their targets from globals at the point of use and mutate the real machine. The seam that
would fix that is [#11](https://github.com/hugoforte/dotfiles/issues/11). Until it lands, do
not add a test that runs any of them — add the seam first.

## Why plain `sh` and not `bats`

`bats` is the better-known tool and the argument for it is real. It lost on two counts: it
would need an entry in `powershell/tools.psd1` and an install on every machine, and
bats-on-Git-Bash is a known source of friction on exactly the platform this repo targets. The
suite is around thirty assertions of "did this equal that", so `assert.sh` carries it.

If the suite outgrows a helper — setup/teardown hooks, tagging, parallelism — `bats` is the
upgrade path and this is the note saying so.

## CI runs windows-latest, and only that

Not a default anyone forgot to change. Both defects this repo has actually shipped were
invisible on any other platform:

- `Write-Host` writes to the information stream, which **Windows PowerShell 5.1** does not
  capture through `| Out-String`. The scheduled task logged a hardcoded `"ok"` for runs that
  warned, for as long as that went unnoticed.
- **jq on Windows emits CRLF**, and `.gitattributes` here is `* text=auto eol=lf`.
  `settings_write_json` strips `\r` for that reason alone.

A Linux runner passes both vacuously. That is worse than not testing them, because it looks
like coverage. For the same reason the workflow's PowerShell steps use `shell: powershell`
(5.1), never `pwsh` (7.x) — 5.1 is what the scheduled task runs.

The markdown step lints an **allowlist** of the docs this repo writes, not the whole tree:
`.github/prompts`, `ai/agents` and `ai/skills` are generated or vendored, carry a few hundred
findings between them, and are not ours to fix. That is the same reasoning
`powershell/markdownlint.jsonc` gives for being an allowlist of rules rather than the stock
set minus exceptions — a linter that is always red gets ignored.

## Adding a test

- Shell: a new `tests/<thing>.test.sh`. `tests/run.sh` finds it; nothing needs registering.
  Source `assert.sh`, work in a temp directory you create and remove.
- PowerShell: a new `tests/<Thing>.Tests.ps1`. Pester discovers it.

One behaviour per assertion, named so a failure reads as a sentence. If a test needs the real
machine to pass, it is the wrong test.

Two traps that have already cost time here:

- **Pester's `TestDrive` is per file, not per test.** Without a `BeforeEach` handing each test
  its own directory, a test sees the links the previous one left behind. `ManagedLink.Tests.ps1`
  calls `New-WorkDir` for exactly this reason.
- **POSIX sh has no `local`.** `ai/install.sh`'s `link()` and `check_link()` assign `src`, `dst`,
  `backup` and `actual` in the *caller's* shell, so a test using those names as its own
  variables gets silently corrupted. `managed-link.test.sh` uses `repo` and `saved`.

And check your suite can fail before you trust it. Break the thing under test in a scratch copy,
confirm the right assertions go red, restore. Every suite here has been through that.
