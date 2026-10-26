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
    printf 'echo "%s $*" >> "%s"\n' "$script" "$log" > "$fixture_dotfiles/macos/$script"
done
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
# sudo -v asks for a password, so fails here, while $work/nopasswd exists: as real sudo does when
# the user's rule says NOPASSWD but another rule matching them does not.
printf '#!/bin/sh\ncase "$1" in\n  -v) [ ! -e "%s" ] ;;\n  -n) exit 0 ;;\n  *) exec "$@" ;;\nesac\n' "$work/nopasswd" > "$stubs/sudo"
printf '#!/bin/sh\ncase "$1" in --prefix) echo /stub ;; install) echo "brew $*" >> "%s" ;; esac\nexit 0\n' \
    "$log" > "$stubs/brew"
printf '#!/bin/sh\nexit 0\n' > "$stubs/jq"
printf '#!/bin/sh\nexit 0\n' > "$stubs/node"
printf '#!/bin/sh\ncase "$1 $2" in\n  "auth status") exit 0 ;;\n  "repo clone") echo "clone $3" >> "%s"; exec git clone --quiet "$3" "$4" ;;\nesac\nexit 1\n' \
    "$log" > "$stubs/gh"
chmod +x "$stubs"/*

HOME="$work/home"; export HOME
PATH="$stubs:$PATH"; export PATH
DOTFILES_URL="$fixture_dotfiles"; export DOTFILES_URL

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
printf '#!/bin/sh\nexit 0\n' > "$stubs/node"
chmod +x "$stubs/node"

touch "$work/nopasswd"
rm -rf "$src"
out="$(run --overlays "$fixture_overlays" --dir "$src")"; rc=$?
assert_eq "passwordless sudo, where sudo -v would still ask, does not stop it" "0" "$rc"
rm "$work/nopasswd"

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

assert_summary "macos-bootstrap"
