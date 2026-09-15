# Git Configuration

Global git identity, symlinked to `~/.gitconfig` and `~/.gitconfig-employer` by `powershell/setup.ps1`.

## Files

- `gitconfig` - the main `~/.gitconfig`: identity, core settings, difftool/mergetool, credential helper.
- `gitconfig-employer` - `user.email` override for `employer` org repos, pulled in via a
  `[includeIf "hasconfig:remote.*.url:https://github.com/employer/**"]` block in `gitconfig`.
  Applies automatically based on the repo's remote URL, regardless of where it's checked out.

## Adding another per-org identity

1. Add a new `gitconfig-<org>` file here with the `[user]` override.
2. Add a matching `includeIf "hasconfig:remote.*.url:https://github.com/<org>/**"` block to `gitconfig`.
3. Add the symlink for the new file in the "Git config" section of `powershell/setup.ps1`.
4. Re-run `setup.ps1` on each machine (or wait for the next `dotfiles-sync`, once new-file linking is added there too).

## Setup on New Machine

`setup.ps1` creates symlinks from `~/.gitconfig` and `~/.gitconfig-employer` to the files in this
directory, backing up any existing real files first. After that, edits made anywhere flow through git.
