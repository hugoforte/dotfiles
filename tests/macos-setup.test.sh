#!/bin/sh

# Fixture suite for macos/setup.sh: the links it makes, the ~/.gitconfig-overlays it writes, the
# Brewfiles it applies, and --check reporting all of it without changing anything.
#
# It runs on any OS. uname, scutil and brew are stubs on PATH: uname says Darwin, scutil names the
# Mac, and brew logs each call to a file instead of installing anything. HOME has a space in it,
# and RIG_ROOT points at an empty directory so the real rig checkout stays out of it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home dir"
stubs="$work/stubs"
personal="$work/private/personal"
second="$work/private/second"
brew_log="$work/brew.log"
mkdir -p "$repo/ai/helpers" "$repo/ai/claude" "$repo/ai/secrets" "$repo/ai/agents" "$repo/ai/skills/own" \
         "$repo/macos" "$home" "$stubs" \
         "$personal/git" "$personal/aws" "$personal/macos" "$personal/machines" \
         "$second/git" "$second/macos"

cp "$REPO_ROOT"/macos/* "$repo/macos/"
cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"

printf '[user]\n\temail = me@example.com\n' > "$personal/git/gitconfig"
printf '[core]\n\teditor = vim\n' > "$second/git/gitconfig"
printf '[profile dev]\n' > "$personal/aws/config"
printf 'brew "jq"\n' > "$personal/macos/Brewfile"
printf 'brew "uv"\n' > "$second/macos/Brewfile"
printf 'cask "ghostty"\n' > "$personal/machines/MACBOOK.Brewfile"

# machine.local.psd1 holds Windows paths on a Windows machine, so on Git Bash write them that way.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
# overlays <dir>...: list these overlays in machine.local.psd1
overlays() {
    {
        printf '@{\n    Overlays = @(\n'
        for dir in "$@"; do printf "        '%s'\n" "$(win "$dir")"; done
        printf '    )\n}\n'
    } > "$repo/ai/secrets/machine.local.psd1"
}
overlays "$personal" "$second"

# The stubs. `brew bundle check` fails while $work/brew-missing exists.
printf '#!/bin/sh\necho "${STUB_UNAME:-Darwin}"\n' > "$stubs/uname"
printf '#!/bin/sh\n[ "$*" = "--get LocalHostName" ] && echo "${STUB_HOSTNAME-macbook}"\n' > "$stubs/scutil"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in "bundle check"*) [ ! -e "%s" ] ;; esac\n' \
    "$brew_log" "$work/brew-missing" > "$stubs/brew"
chmod +x "$stubs/uname" "$stubs/scutil" "$stubs/brew"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT
PATH="$stubs:$PATH"; export PATH

run()       { (cd "$work" && sh "$repo/macos/setup.sh" "$@" 2>&1); }
install()   { run > /dev/null; }
check()     { run --check; }
says()      { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
exists()    { if [ -e "$1" ] || [ -L "$1" ]; then echo y; else echo n; fi; }

# --- install ---------------------------------------------------------------------------------

printf '# my old zshrc\n' > "$home/.zshrc"
install; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "~/.zshrc is linked to macos/zshrc" "$repo/macos/zshrc" "$(readlink "$home/.zshrc")"
set -- "$home"/.zshrc.backup.*
assert_eq "the real ~/.zshrc it displaced is backed up" "# my old zshrc" "$(cat "$1")"
assert_eq "~/.gitconfig is linked to macos/gitconfig" "$repo/macos/gitconfig" "$(readlink "$home/.gitconfig")"
assert_eq "~/.aws/config is linked to the one overlay that has it" "$personal/aws/config" "$(readlink "$home/.aws/config")"
assert_eq "~/.gitconfig-overlays includes each overlay's git/gitconfig, in order" \
    "$(printf '[include]\n\tpath = %s\n[include]\n\tpath = %s' "$personal/git/gitconfig" "$second/git/gitconfig")" \
    "$(grep -v '^#' "$home/.gitconfig-overlays")"
assert_eq "brew bundle applies each overlay's Brewfile, then the machine's" \
    "$(printf 'bundle --file=%s\nbundle --file=%s\nbundle --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile" "$personal/machines/MACBOOK.Brewfile")" \
    "$(cat "$brew_log")"
assert_eq "ai/install.sh runs: ~/.claude/CLAUDE.md is linked" "$repo/ai/CLAUDE.md" "$(readlink "$home/.claude/CLAUDE.md")"

# --- check -----------------------------------------------------------------------------------

rm -f "$brew_log"
out="$(check)"; rc=$?
assert_eq "--check is clean once installed" "0" "$rc"
assert_eq "--check only asks brew, never installs" \
    "$(printf 'bundle check --file=%s\nbundle check --file=%s\nbundle check --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile" "$personal/machines/MACBOOK.Brewfile")" \
    "$(cat "$brew_log")"

rm "$home/.zshrc"
out="$(check)"; rc=$?
assert_eq "--check fails on a missing link" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" ".zshrc missing")"
assert_eq "--check does not make it" "n" "$(exists "$home/.zshrc")"
install

printf '# edited\n' >> "$home/.gitconfig-overlays"
out="$(check)"; rc=$?
assert_eq "--check fails on a stale ~/.gitconfig-overlays" "1" "$rc"
install
out="$(check)"; rc=$?
assert_eq "install rewrites ~/.gitconfig-overlays" "0" "$rc"

touch "$work/brew-missing"
out="$(check)"; rc=$?
assert_eq "--check fails when a Brewfile is not fully installed" "1" "$rc"
assert_eq "--check names the Brewfile" "y" "$(says "$out" "$second/macos/Brewfile")"
rm "$work/brew-missing"

rm "$home/.claude/CLAUDE.md"
out="$(check)"; rc=$?
assert_eq "--check fails on ai/install.sh's drift too" "1" "$rc"
install

# --- the machine's own Brewfile --------------------------------------------------------------

rm -f "$brew_log"
STUB_HOSTNAME="" install
assert_eq "a Mac with no LocalHostName applies the overlays' Brewfiles alone" \
    "$(printf 'bundle --file=%s\nbundle --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile")" \
    "$(cat "$brew_log")"
out="$(STUB_HOSTNAME="" check)"; rc=$?
assert_eq "and --check fails, since the Mac is not named yet" "1" "$rc"
assert_eq "and says how to name it" "y" "$(says "$out" "LocalHostName")"

mkdir -p "$second/machines"
printf 'cask "zed"\n' > "$second/machines/MACBOOK.Brewfile"
out="$(run)"; rc=$?
assert_eq "a machine Brewfile in two overlays fails" "1" "$rc"
assert_eq "and names both" "y" "$(says "$out" "$second/machines/MACBOOK.Brewfile")"
rm -r "$second/machines"

# --- refusals --------------------------------------------------------------------------------

mkdir -p "$repo/aws"
printf '[profile other]\n' > "$repo/aws/config"
out="$(run)"; rc=$?
assert_eq "aws/config from two sources fails" "1" "$rc"
assert_eq "and names both" "y" "$(says "$out" "$repo/aws/config")"
rm -r "$repo/aws"

overlays "$personal" "$work/private/gone"
out="$(run)"; rc=$?
assert_eq "a listed overlay that does not exist fails" "1" "$rc"
assert_eq "and names it" "y" "$(says "$out" "gone")"
overlays "$personal" "$second"

out="$(STUB_UNAME=Linux run)"; rc=$?
assert_eq "anywhere but macOS it refuses" "1" "$rc"
assert_eq "and points at the Windows setup" "y" "$(says "$out" "powershell/setup.ps1")"

assert_summary "macos/setup.sh"
