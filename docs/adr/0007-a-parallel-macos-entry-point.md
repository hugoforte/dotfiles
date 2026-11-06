# A Mac has its own entry point, macos/, beside powershell/

A Mac is set up by `macos/setup.sh`, a POSIX sh script written for it, not by porting
`powershell/` to run there. The two entry points share what is already portable: `ai/install.sh`,
`bin/`, the overlay layout and `ai/secrets/machine.local.psd1`, which `macos/` reads with the
same awk reader `ai/install.sh` uses (`ai/helpers/overlays.sh`).

Porting `powershell/` was the obvious alternative, since PowerShell 7 runs on macOS. It was
rejected because almost nothing in `powershell/` is about PowerShell: it is about Windows.
`mklink` and Developer Mode, the HKCU user PATH, scheduled tasks, winget, UAC elevation and
`$env:COMPUTERNAME` each have a macOS counterpart that works differently (`ln -s`, `~/.zshrc`,
launchd, Homebrew, no elevation, `scutil`). A port would be a second implementation behind
`if ($IsMacOS)` in every script, and would make PowerShell 7 a dependency on a machine whose
shell is zsh. The scheduled task also runs Windows PowerShell 5.1, which differs from 7 on exactly
the behaviour `tests/` pins ([0004](0004-ci-runs-windows-only.md)), so one script serving both
would be tested under neither.

What the two entry points must agree on is the contract, not the code: the same managed links
policy ([0003](0003-back-up-then-link.md), shared in sh through `ai/helpers/managed-link.sh`),
the same overlay rules (`aws/config` merged from every source, as amended by
[0010](0010-aws-config-is-generated.md), every `git/gitconfig` included in overlay
order, a missing overlay is an error), and a check mode that changes nothing and exits 1 on
drift. A Mac has its own `macos/gitconfig` because `git/gitconfig` names the Windows path of
`gh.exe` and sets `autocrlf = true`.
