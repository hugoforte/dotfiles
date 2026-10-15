#!/bin/sh

# Fixture suite for macos/zshrc, sourced through a ~/.zshrc symlink as macos/setup.sh leaves it:
# it finds this checkout through the link and puts bin/ on PATH. Needs zsh, so it runs on the
# macOS job and says it skipped where zsh is missing.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Physical, as zsh's :A resolves it.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

. "$SCRIPT_DIR/assert.sh"

if ! command -v zsh > /dev/null 2>&1; then
    printf '  SKIP  zsh is not installed here\n'
    exit 0
fi

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

home="$work/home dir"
mkdir -p "$home"
ln -s "$REPO_ROOT/macos/zshrc" "$home/.zshrc"

# in_zsh <command>: run it after sourcing ~/.zshrc, in a zsh that reads no other startup file
in_zsh() { HOME="$home" zsh -f -c ". \"\$HOME/.zshrc\" && $1" 2>&1; }

assert_eq "it finds this checkout through the ~/.zshrc link" "$REPO_ROOT" "$(in_zsh 'print -r -- $DOTFILES')"
assert_eq "it puts bin/ first on PATH" "$REPO_ROOT/bin" "$(in_zsh 'print -r -- $path[1]')"
assert_eq "bin/ commands resolve from there" "$REPO_ROOT/bin/md-lint" "$(in_zsh 'whence -p md-lint')"
assert_eq "dotfiles-check is defined" "function" "$(in_zsh 'whence -w dotfiles-check' | sed 's/.*: //')"

assert_summary "macos/zshrc"
