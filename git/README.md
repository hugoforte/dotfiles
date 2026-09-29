# Git Configuration

Global git identity, symlinked to `~/.gitconfig` by `powershell/setup.ps1`, which also writes `~/.gitconfig-overlays`.

## Files

- `gitconfig` - the main `~/.gitconfig`: identity, core settings, difftool/mergetool, credential helper. Its last line includes `~/.gitconfig-overlays`, so anything an overlay sets wins over it.

## Overlays

`~/.gitconfig-overlays` is generated, not linked: one `[include]` per overlay listed in `ai/secrets/machine.local.psd1` that ships a `git/gitconfig`, in the order listed. A machine with no overlays gets a file with only its header comment. Git ignores a missing include, so a machine that has not run `setup.ps1` or `sync.ps1` since is unaffected. `setup.ps1 -Check` reports the file as drift when it is missing or out of date, and `sync.ps1` rewrites it.

## Adding a per-org identity

Put it in an overlay, never here: an overlay's `git/gitconfig` holds an `includeIf "hasconfig:remote.*.url:https://github.com/<org>/**"` block whose `path` names a file beside it (a relative path resolves against the including file), and that file holds the `[user]` override. It applies on the next `sync.ps1` or `setup.ps1` run, based on each repo's remote URL, wherever the repo is checked out.

## Setup on New Machine

`setup.ps1` creates the symlink from `~/.gitconfig` to `gitconfig`, backing up any existing real file first, and writes `~/.gitconfig-overlays`. After that, edits made anywhere flow through git.
