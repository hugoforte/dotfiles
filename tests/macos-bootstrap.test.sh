#!/bin/sh

# Fixture suite for macos/bootstrap.sh: it names the Mac, clones dotfiles and an overlay repo,
# writes machine.local.psd1, runs setup, the sync agent and each overlay's own bootstrap in that
# order, and a second run clones and writes nothing.
#
# It runs on any OS, offline. uname, scutil, sudo, brew, gh, jq and node are stubs on PATH: gh
# clones with plain git, from fixture repos on disk, and brew logs what it installs. The cloned
# dotfiles' macos/ scripts are stubs that log.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
work="$(cd "$work" && pwd -P)"

stubs="$work/stubs"
log="$work/calls.log"
src="$work/src dir"
mkdir -p "$stubs" "$work/home"

# git_repo <dir>: commit everything in <dir> as a repo to clone from
git_repo() {
    git -C "$1" init --quiet && git -C "$1" add -A &&
        git -C "$1" -c user.name=t -c user.email=t@example.com commit --quiet -m fixture
}

# The dotfiles to clone: the real overlay reader, and macos/ scripts that log their own name.
fixture_dotfiles="$work/fixture-dotfiles"
mkdir -p "$fixture_dotfiles/macos" "$fixture_dotfiles/ai/helpers" "$fixture_dotfiles/ai/secrets"
cp "$REPO_ROOT/ai/helpers/overlays.sh" "$REPO_ROOT/ai/helpers/generated-file.sh" "$REPO_ROOT/ai/helpers/aws-config.sh" "$fixture_dotfiles/ai/helpers/"
for script in setup.sh install-sync-agent.sh deploy-secrets.sh; do
    printf 'echo "%s $*" >> "%s"\nexit 0\n' "$script" "$log" > "$fixture_dotfiles/macos/$script"
done
# setup.sh installs a cask, which runs sudo.
printf 'echo "setup.sh $*" >> "%s"\nbrew cask-install || exit 1\nexit 0\n' "$log" > "$fixture_dotfiles/macos/setup.sh"
cp "$REPO_ROOT/ai/secrets/machine.local.psd1.example" "$fixture_dotfiles/ai/secrets/"
printf '/ai/secrets/machine.local.psd1\n' > "$fixture_dotfiles/.gitignore"
git_repo "$fixture_dotfiles"

# The overlay repo: two overlays, one with its own bootstrap.
fixture_overlays="$work/private"
mkdir -p "$fixture_overlays/personal/macos" "$fixture_overlays/company"
printf 'echo "personal bootstrap" >> "%s"\n' "$log" > "$fixture_overlays/personal/macos/bootstrap.sh"
printf 'company\n' > "$fixture_overlays/company/README"
git_repo "$fixture_overlays"

printf '#!/bin/sh\necho Darwin\n' > "$stubs/uname"
printf '#!/bin/sh\ncase "$1" in\n  --get) cat "%s" 2>/dev/null ;;\n  --set) echo "scutil $*" >> "%s"; [ "$2" = LocalHostName ] && printf "%%s" "$3" > "%s" ;;\nesac\nexit 0\n' \
    "$work/hostname" "$log" "$work/hostname" > "$stubs/scutil"
# sudo: see the stub's own comment for the state it keeps in $STUB_STATE.
STUB_STATE="$work/sudo-state"; export STUB_STATE
mkdir -p "$STUB_STATE"
cp "$SCRIPT_DIR/macos-bootstrap-sudo-stub.sh" "$stubs/sudo"
# brew logs each install, and "brew would ask" for one run without HOMEBREW_NO_ASK=1: on a terminal,
# Homebrew 7 asks before installing. "brew cask-install" runs sudo as Homebrew does for a cask's
# installer: it forgets the cached credentials first (utils/sudo.sh runs sudo --reset-timestamp), and
# passes -A when SUDO_ASKPASS is set (system_command.rb).
printf '#!/bin/sh\ncase "$1" in --prefix) echo /stub ;; install) echo "brew $*" >> "%s"; [ "${HOMEBREW_NO_ASK:-}" = 1 ] || echo "brew would ask" >> "%s" ;;\n  cask-install) sudo -k; if [ -n "${SUDO_ASKPASS:-}" ]; then sudo -A -E -- true; else sudo -E -- true; fi || exit 1 ;; esac\nexit 0\n' \
    "$log" "$log" > "$stubs/brew"
printf '#!/bin/sh\nexit 0\n' > "$stubs/jq"
printf '#!/bin/sh\nexit 0\n' > "$stubs/node"
# gh repo clone <url> <dir> [-- <git clone options>]: logs the url, then clones with those options.
printf '#!/bin/sh\ncase "$1 $2" in\n  "auth status") exit 0 ;;\n  "repo clone") echo "clone $3" >> "%s"; url="$3"; dir="$4"; shift 4; [ "${1:-}" = -- ] && shift; exec git clone "$@" "$url" "$dir" ;;\nesac\nexit 1\n' \
    "$log" > "$stubs/gh"
chmod +x "$stubs"/*

HOME="$work/home"; export HOME
PATH="$stubs:$PATH"; export PATH
DOTFILES_URL="$fixture_dotfiles"; export DOTFILES_URL

# bootstrap.sh reads the password from stdin when sudo needs one, so a run that is not handed one
# reads an empty stdin rather than waiting on the terminal this suite was started from.
exec < /dev/null
run() { sh "$REPO_ROOT/macos/bootstrap.sh" "$@" 2>&1; }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }

echo "macos/bootstrap.sh"

out="$(run)"; rc=$?
assert_eq "without --overlays it fails" "1" "$rc"
assert_eq "... and says it is required" "y" "$(says "$out" "--overlays is required")"

printf 'old' > "$work/hostname"
out="$(run --overlays "$fixture_overlays" --name MACBOOK --dir "$src")"; rc=$?
assert_eq "a first run succeeds" "0" "$rc"
[ "$rc" = 0 ] || printf "%s\n" "$out"
assert_eq "it names the Mac" "MACBOOK" "$(cat "$work/hostname")"
assert_eq "it clones dotfiles and the overlay repo" \
    "$(printf 'clone %s\nclone %s' "$fixture_dotfiles" "$fixture_overlays")" \
    "$(grep '^clone ' "$log")"
assert_eq "it lists every overlay in the repo, with the folder as the search root" \
    "$(printf "    SearchRoots = @('%s')\n    Overlays = @(\n        '%s/private/company'\n        '%s/private/personal'\n    )" "$src" "$src" "$src")" \
    "$(sed -n '/SearchRoots/,/^    )/p' "$src/dotfiles/ai/secrets/machine.local.psd1")"
assert_eq "it installs none of gh, jq and node when each is on PATH" "" "$(grep '^brew ' "$log")"
assert_eq "it runs setup, the sync agent and the overlay's bootstrap, in order, then deploys and checks" \
    "$(printf 'setup.sh \ninstall-sync-agent.sh \npersonal bootstrap\ndeploy-secrets.sh \nsetup.sh --check')" \
    "$(grep -v '^clone \|^scutil ' "$log")"

before="$(cat "$src/dotfiles/ai/secrets/machine.local.psd1")"
: > "$log"
out="$(run --overlays "$fixture_overlays" --name MACBOOK --dir "$src")"; rc=$?
assert_eq "a second run succeeds" "0" "$rc"
assert_eq "... clones nothing and renames nothing" "" "$(grep '^clone \|^scutil ' "$log")"
assert_eq "... and leaves machine.local.psd1 as it was" "$before" "$(cat "$src/dotfiles/ai/secrets/machine.local.psd1")"

rm -rf "$src"
: > "$log"
out="$(run --overlays "$fixture_overlays" --only personal --dir "$src")"; rc=$?
assert_eq "--only lists just the overlays it names" \
    "$(printf "        '%s/private/personal'" "$src")" \
    "$(grep "^        '" "$src/dotfiles/ai/secrets/machine.local.psd1")"

# DOTFILES_BRANCH and OVERLAY_BRANCH clone each repo at its branch.
git -C "$fixture_dotfiles" branch --quiet feat/try
git -C "$fixture_overlays" branch --quiet feat/try
rm -rf "$src"
out="$(DOTFILES_BRANCH=feat/try OVERLAY_BRANCH=feat/try run --overlays "$fixture_overlays" --only personal --dir "$src")"; rc=$?
assert_eq "with DOTFILES_BRANCH and OVERLAY_BRANCH a first run succeeds" "0" "$rc"
[ "$rc" = 0 ] || printf "%s\n" "$out"
assert_eq "... dotfiles is cloned at DOTFILES_BRANCH" "feat/try" "$(git -C "$src/dotfiles" branch --show-current)"
assert_eq "... and the overlay repo at OVERLAY_BRANCH" "feat/try" "$(git -C "$src/private" branch --show-current)"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --only personal --dir "$src")"; rc=$?
assert_eq "without them, each is cloned at its default branch" \
    "$(git -C "$fixture_dotfiles" branch --show-current)" "$(git -C "$src/dotfiles" branch --show-current)"

rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --only missing --dir "$src")"; rc=$?
assert_eq "--only with an overlay the repo lacks fails" "1" "$rc"
assert_eq "... and names it" "y" "$(says "$out" "has no overlay named missing")"

# PATH without every directory that holds a node, the stub's included, so node cannot be found.
rm "$stubs/node"
no_node_path="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do
    [ -n "$dir" ] && [ ! -x "$dir/node" ] && [ ! -x "$dir/node.exe" ] && printf '%s:' "$dir"
done)"
: > "$log"
out="$(PATH="$no_node_path" run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "a Mac without node succeeds" "0" "$rc"
assert_eq "... and has brew install node, before setup runs" \
    "$(printf 'brew install node\nsetup.sh ')" \
    "$(grep '^brew \|^setup.sh' "$log" | head -2)"
assert_eq "... without brew stopping to ask" "" "$(grep '^brew would ask' "$log")"
printf '#!/bin/sh\nexit 0\n' > "$stubs/node"
chmod +x "$stubs/node"

touch "$STUB_STATE/nopasswd"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "passwordless sudo, where sudo -v would still ask, does not stop it" "0" "$rc"
rm "$STUB_STATE/nopasswd"

# A Mac whose sudo wants a password: asked once, on stdin; Homebrew then forgets sudo's cached
# credentials before each cask's installer, which would ask again but for SUDO_ASKPASS.
touch "$STUB_STATE/pwreq"
rm -rf "$src"; : > "$STUB_STATE/log"
out="$(printf 'secret\n' | run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "a password sudo accepts lets the run finish" "0" "$rc"
[ "$rc" = 0 ] || printf "%s\n" "$out"
assert_eq "sudo asks nobody again, though Homebrew forgot its cached credentials" "" "$(grep '^sudo asked' "$STUB_STATE/log")"
askpass="$(sed -n 's/^sudo askpass //p' "$STUB_STATE/log" | head -1)"
assert_eq "Homebrew's sudo asked through a SUDO_ASKPASS helper" "y" "$([ -n "$askpass" ] && echo y || echo n)"
assert_eq "the helper and the password it hands out are gone when the run ends" "n" \
    "$([ -n "$askpass" ] && { [ -e "$askpass" ] || [ -e "$(dirname "$askpass")" ]; } && echo y || echo n)"

rm -rf "$src"
out="$(printf 'wrong\nwrong\nwrong\n' | run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "a password sudo refuses three times fails the run" "1" "$rc"
assert_eq "... which says sudo is needed" "y" "$(says "$out" "sudo is needed")"
rm "$STUB_STATE/pwreq"

# Two overlays whose aws/config both declare one section, which the merged ~/.aws/config cannot hold.
mkdir -p "$fixture_overlays/personal/aws" "$fixture_overlays/company/aws"
printf '[default]\n' > "$fixture_overlays/personal/aws/config"
printf '[default]\n' > "$fixture_overlays/company/aws/config"
git -C "$fixture_overlays" add -A
git -C "$fixture_overlays" -c user.name=t -c user.email=t@example.com commit --quiet -m "clash"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "overlays that clash fail the run" "1" "$rc"
assert_eq "... naming the section both declare" "y" "$(says "$out" "aws/config section [profile default] is in both")"
assert_eq "... before machine.local.psd1 is written" "n" "$([ -f "$src/dotfiles/ai/secrets/machine.local.psd1" ] && echo y || echo n)"
git -C "$fixture_overlays" rm --quiet -r personal/aws

# Two overlays that register the same skill.
mkdir -p "$fixture_overlays/personal/ai/secrets" "$fixture_overlays/company/ai/secrets"
for o in personal company; do
    printf "@{\n    Skills = @(\n        @{\n            Id    = 'tool'\n            Files = @('.env')\n        }\n    )\n}\n" > "$fixture_overlays/$o/ai/secrets/registry.psd1"
done
git -C "$fixture_overlays" add -A
git -C "$fixture_overlays" -c user.name=t -c user.email=t@example.com commit --quiet -m "same skill"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "overlays that register the same skill fail the run" "1" "$rc"
assert_eq "... before machine.local.psd1 is written" "n" "$([ -f "$src/dotfiles/ai/secrets/machine.local.psd1" ] && echo y || echo n)"
git -C "$fixture_overlays" rm --quiet -r personal/ai
git -C "$fixture_overlays" -c user.name=t -c user.email=t@example.com commit --quiet -m "no clash"

printf 'exit 3\n' >> "$fixture_overlays/personal/macos/bootstrap.sh"
git -C "$fixture_overlays" -c user.name=t -c user.email=t@example.com commit --quiet -am "fail"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "a failing overlay bootstrap fails the run" "1" "$rc"

# An overlay bootstrap that reads stdin, as an installer does, must not swallow the next one.
mkdir -p "$fixture_overlays/company/macos"
printf 'echo "personal bootstrap" >> "%s"\n' "$log" > "$fixture_overlays/personal/macos/bootstrap.sh"
printf 'cat > /dev/null\necho "company bootstrap" >> "%s"\n' "$log" > "$fixture_overlays/company/macos/bootstrap.sh"
git -C "$fixture_overlays" add -A
git -C "$fixture_overlays" -c user.name=t -c user.email=t@example.com commit --quiet -m "two bootstraps"
rm -rf "$src" "$log"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "overlay bootstraps run" "0" "$rc"
assert_eq "an overlay bootstrap that reads stdin does not stop the next from running" "y" "$(grep -q 'personal bootstrap' "$log" && echo y || echo n)"

# A here-document that cannot be created, as on a full disk, skips the loop that runs the overlays'
# bootstraps. That fails the run. A file size limit of zero (with SIGXFSZ ignored) makes bash fail
# so; a shell that keeps here-documents in memory (bash 5.1 and later) cannot, and skips this.
no_files() { (ulimit -f 0 && trap '' XFSZ && "$@"); }
probe="$(no_files sh -c 'cat <<EOF > /dev/null
x
EOF' 2>&1)"
if [ -z "$probe" ]; then
    echo "  SKIP  this shell's here-documents do not fail with a file size limit of zero"
else
    # git writes files, so under the limit it is a stub that pulls nothing; the clones are in place.
    mkdir "$work/git-stub"
    printf '#!/bin/sh\nexit 0\n' > "$work/git-stub/git"
    chmod +x "$work/git-stub/git"
    out="$(PATH="$work/git-stub:$PATH" no_files run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
    assert_eq "a here-document that cannot be created fails the run" "1" "$rc"
    assert_eq "... which says so" "y" "$(says "$out" "Bootstrap finished with failures")"
    assert_eq "... and does not say it is complete" "n" "$(says "$out" "Bootstrap complete")"
fi

assert_summary "macos-bootstrap"
