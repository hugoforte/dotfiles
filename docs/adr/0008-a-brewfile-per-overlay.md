# A Mac's tools are Brewfiles, one per overlay and one per machine

A Mac installs its tools with `brew bundle`, from each overlay's `macos/Brewfile` in overlay
order, then from the one `machines/<KEY>.Brewfile` an overlay ships for it, `<KEY>` being the
Mac's `HostName` uppercased (its `LocalHostName` when no `HostName` is set). `macos/setup.sh --check` asks `brew bundle check` of each.
Both run with `--no-upgrade`: as with a manifest on Windows, an entry is installed when missing
and never upgraded, so an outdated formula is neither drift nor something a run replaces.
Anything Homebrew cannot install is a manual step in the machine's notes.

`powershell/tools.psd1` stays Windows-only. Extending it to macOS was the alternative that keeps
one list of tools, and it was rejected because the list is not really one list. Its entries are
winget ids, npm packages and GitHub release assets with Windows install methods, and
`Unattended` flags that exist because of UAC; a Mac entry would share the name and nothing else.
A Brewfile is Homebrew's own format, `brew bundle` already installs, checks and reports it, and
none of `install-tools.ps1`'s machinery (options, deferred entries) has a use on a single Mac.
A second Mac with a different job gets its own machine Brewfile before options come to macOS
as code.

This repo ships no Brewfile of its own: like `aws/config`, which tools a machine wants is a
private choice, so the Brewfiles live in overlays. The machine key follows the Windows one,
`machines/<COMPUTERNAME>.psd1`, and comes from `scutil` because a Mac's other names
(`ComputerName`, `HostName`) may hold spaces or be unset.

Amended: the `HostName` comes first, because Bonjour renames the `LocalHostName` by itself while
another Mac on the network holds the name (`MACBOOK` becomes `MACBOOK-2`), as the old Mac does
while its replacement is set up; a key read from it then names no Brewfile, silently. Nothing
renames the `HostName` but a person, and `macos/bootstrap.sh` sets it with the other two.

Amended: what dotfiles itself needs is not a private choice, so no overlay has to carry it.
`macos/bootstrap.sh` installs `gh`, `jq` and `node` with `brew install` when each is missing:
`gh` clones, `jq` merges Claude Code's settings, and `node` runs the hooks those settings hold,
whose `agent-guard` blocks every Bash call when it cannot start. `macos/setup.sh` fails, and
`--check` reports drift, when no `node` is found after the Brewfiles.
