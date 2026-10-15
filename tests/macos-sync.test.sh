#!/bin/sh

# Fixture suite for macos/sync.sh: it pulls this repo and each overlay repo, runs macos/setup.sh
# with --brew-if-changed, deploys secrets only when machine.local.psd1 declares SearchRoots, and
# logs each step to ~/Library/Logs/dotfiles-sync.log.
#
# The repo and the overlay repo are clones of fixture origins, so the pulls are real. uname,
# scutil and brew are stubs on PATH, as in macos-setup.test.sh, and so is sops.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

home="$work/home dir"
stubs="$work/stubs"
brew_log="$work/brew.log"
mkdir -p "$home" "$stubs"

GIT_AUTHOR_NAME=test; GIT_AUTHOR_EMAIL=test@example.com
GIT_COMMITTER_NAME=test; GIT_COMMITTER_EMAIL=test@example.com
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# The dotfiles seed: what sync.sh needs of this repo, committed and pushed to a bare origin.
seed="$work/seed"
mkdir -p "$seed/ai/helpers" "$seed/ai/claude" "$seed/ai/secrets" "$seed/ai/agents" "$seed/ai/skills/own" "$seed/macos"
cp "$REPO_ROOT"/macos/* "$seed/macos/"
cp "$REPO_ROOT/ai/install.sh" "$seed/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$seed/ai/helpers/"
printf 'exit 0\n' > "$seed/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$seed/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$seed/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$seed/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$seed/ai/claude/settings.json"
printf 'ai/secrets/machine.local.psd1\n' > "$seed/.gitignore"
git init -q "$seed" && git -C "$seed" add -A && git -C "$seed" commit -q -m seed
git clone -q --bare "$seed" "$work/dotfiles.git"
git clone -q "$work/dotfiles.git" "$work/dotfiles"
repo="$work/dotfiles"

# An overlay repo holding one overlay, with a Brewfile.
overlay_seed="$work/overlay-seed"
mkdir -p "$overlay_seed/personal/macos"
printf 'brew "jq"\n' > "$overlay_seed/personal/macos/Brewfile"
git init -q "$overlay_seed" && git -C "$overlay_seed" add -A && git -C "$overlay_seed" commit -q -m seed
git clone -q --bare "$overlay_seed" "$work/private.git"
git clone -q "$work/private.git" "$work/private"
personal="$work/private/personal"

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"

printf '#!/bin/sh\necho Darwin\n' > "$stubs/uname"
printf '#!/bin/sh\necho macbook\n' > "$stubs/scutil"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$brew_log" > "$stubs/brew"
printf '#!/bin/sh\necho "sops $*" >> "%s"\n' "$work/sops.log" > "$stubs/sops"
chmod +x "$stubs/uname" "$stubs/scutil" "$stubs/brew" "$stubs/sops"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT
PATH="$stubs:$PATH"; export PATH

log="$home/Library/Logs/dotfiles-sync.log"
sync()  { (cd "$work" && sh "$repo/macos/sync.sh" "$@" 2>&1); }
says()  { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }

# --- a first run -----------------------------------------------------------------------------

# A real ~/.zshrc, so setup warns that it backed it up and the log has a warning to carry.
printf '# old\n' > "$home/.zshrc"
out="$(sync)"; rc=$?
assert_eq "sync succeeds" "0" "$rc"
assert_eq "it logs to ~/Library/Logs/dotfiles-sync.log" "y" "$(says "$(cat "$log")" "sync start")"
assert_eq "and to the terminal" "y" "$(says "$out" "sync start")"
assert_eq "it runs macos/setup.sh: ~/.zshrc is linked" "$repo/macos/zshrc" "$(readlink "$home/.zshrc")"
assert_eq "it applies the Brewfile the first time" "1" "$(grep -c '^bundle --no-upgrade --file=' "$brew_log")"
assert_eq "it skips the secrets with no SearchRoots" "y" "$(says "$(cat "$log")" "deploy-secrets.sh skipped")"
assert_eq "it logs setup's warnings" "y" "$(says "$(cat "$log")" "[!!] $home/.zshrc was not a symlink")"
assert_eq "without their colour codes" "n" "$(says "$(cat "$log")" "$(printf '\033')")"

# --- what the pulls bring --------------------------------------------------------------------

branch="$(git -C "$seed" symbolic-ref --short HEAD)"
printf '# instructions, edited\n' > "$seed/ai/CLAUDE.md"
git -C "$seed" commit -q -am "edit CLAUDE.md" && git -C "$seed" push -q "$work/dotfiles.git" "HEAD:$branch"
printf 'brew "uv"\n' >> "$overlay_seed/personal/macos/Brewfile"
git -C "$overlay_seed" commit -q -am "add uv" && git -C "$overlay_seed" push -q "$work/private.git" "HEAD:$branch"
rm -f "$brew_log"

out="$(sync --quiet)"; rc=$?
assert_eq "a second sync succeeds" "0" "$rc"
assert_eq "--quiet writes nothing to the terminal" "" "$out"
assert_eq "it pulls this repo" "# instructions, edited" "$(cat "$repo/ai/CLAUDE.md")"
assert_eq "it pulls the overlay repo" "y" "$(says "$(cat "$personal/macos/Brewfile")" "uv")"
assert_eq "it applies the Brewfile that changed in the same run" "1" "$(grep -c '^bundle --no-upgrade --file=' "$brew_log")"
rm -f "$brew_log"
sync --quiet > /dev/null
assert_eq "and leaves brew alone once nothing changed" "" "$(cat "$brew_log" 2>/dev/null)"

# --- failures --------------------------------------------------------------------------------

git -C "$work/private" remote set-url origin "$work/gone.git"
out="$(sync)"; rc=$?
assert_eq "an overlay repo that cannot be pulled fails the run" "1" "$rc"
assert_eq "and is logged" "y" "$(says "$(cat "$log")" "git pull failed in ")"
assert_eq "but the rest still runs" "y" "$(says "$out" "macos/setup.sh ok")"
git -C "$work/private" remote set-url origin "$work/private.git"

printf "@{\n    SearchRoots = @('%s')\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$work")" "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"
out="$(sync)"; rc=$?
assert_eq "with SearchRoots it deploys the secrets" "y" "$(says "$(cat "$log")" "deploy-secrets.sh ok")"

assert_summary "macos/sync.sh"
