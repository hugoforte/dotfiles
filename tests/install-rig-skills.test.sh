#!/bin/sh

# Fixture suite for the rig-skills component of ai/install.sh: the skills a rig
# checkout ships, linked into the agents' skills directories beside this repo's
# own, and pruned when rig stops shipping one.
#
# RIG_ROOT names the checkout outright and is never fallen through, which is
# what lets this suite point it at a fixture on a machine that has a real rig
# at C:\rig, and at an empty directory to stand for a machine with none.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home"
rig="$work/rig"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/own" "$repo/ai/agents" "$repo/ai/secrets" \
         "$home/.claude/skills" "$rig/bin" "$rig/skills/rig" "$rig/skills/rig-doomed"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
: > "$rig/bin/rig.mjs"
printf -- '---\nname: rig\n---\n' > "$rig/skills/rig/SKILL.md"
printf -- '---\nname: rig-doomed\n---\n' > "$rig/skills/rig-doomed/SKILL.md"

HOME="$home"; export HOME
RIG_ROOT="$rig"; export RIG_ROOT

own()     { sh "$repo/ai/install.sh" --skills-only > /dev/null 2>&1; }
rigs()    { sh "$repo/ai/install.sh" --rig-skills-only "$@" > /dev/null 2>&1; }
check()   { sh "$repo/ai/install.sh" --check --rig-skills-only 2>&1; }
is_link() { if [ -L "$1" ]; then echo y; else echo n; fi; }

own
rigs
assert_eq "rig's skill links on install" "y" "$(is_link "$home/.claude/skills/rig")"
assert_eq "the link points into the rig checkout" "$rig/skills/rig" "$(readlink "$home/.claude/skills/rig")"
assert_eq "this repo's own skill links beside it" "y" "$(is_link "$home/.claude/skills/own")"

out="$(check)"; rc=$?
assert_eq "--check is clean with everything linked" "0" "$rc"

# rig stops shipping a skill, as `rig update` would leave it.
rm -rf "$rig/skills/rig-doomed"

out="$(check)"; rc=$?
assert_eq "--check fails on the link rig left behind" "1" "$rc"
case "$out" in *"skills/rig-doomed"*) named=y ;; *) named=n ;; esac
assert_eq "--check names it" "y" "$named"

rigs
if [ -L "$home/.claude/skills/rig-doomed" ] || [ -e "$home/.claude/skills/rig-doomed" ]; then gone=n; else gone=y; fi
assert_eq "install prunes it" "y" "$gone"
assert_eq "and leaves rig's surviving skill linked" "y" "$(is_link "$home/.claude/skills/rig")"
assert_eq "and leaves this repo's skill alone" "y" "$(is_link "$home/.claude/skills/own")"

# The shipped-skills prune only undoes its own work: a dangling link into rig's
# checkout is the rig component's to remove.
rm -rf "$rig/skills/rig"
own
assert_eq "the shipped-skills prune leaves a dangling rig link alone" "y" "$(is_link "$home/.claude/skills/rig")"
rigs
assert_eq "the rig-skills prune removes it" "n" "$(is_link "$home/.claude/skills/rig")"
mkdir -p "$rig/skills/rig"
printf -- '---\nname: rig\n---\n' > "$rig/skills/rig/SKILL.md"
rigs
assert_eq "and links it again once rig ships it again" "y" "$(is_link "$home/.claude/skills/rig")"

rigs --uninstall
assert_eq "--uninstall removes rig's links" "n" "$(is_link "$home/.claude/skills/rig")"
assert_eq "and not this repo's" "y" "$(is_link "$home/.claude/skills/own")"

# A machine with no rig at all: nothing linked, nothing drifted.
RIG_ROOT="$work/nowhere"; export RIG_ROOT
out="$(check)"; rc=$?
assert_eq "--check is clean on a machine without rig" "0" "$rc"
rigs
assert_eq "install links nothing on a machine without rig" "n" "$(is_link "$home/.claude/skills/rig")"

assert_summary "install.sh rig skills"
