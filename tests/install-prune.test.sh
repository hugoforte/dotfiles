#!/bin/sh

# Fixture suite for the orphan-link pruning in ai/install.sh.
#
# install.sh derives ZSH from its own location and takes the home directories
# from $HOME, so a copy of the repo tree in a temp directory, with $HOME
# pointed at that same directory, installs into fixtures and touches nothing
# real.
#
# What is under test is what happens to the link left behind when a skill is
# deleted from the repo. Both loops in install.sh walk ai/skills/*/, the repo
# side, so before this the stale link survived every install and --check
# called the machine clean while an agent was still listing a skill it could
# no longer read.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

# Git Bash's `ln -s` silently copies unless native symlinks are enabled.
# install.sh turns them on for itself; the fixture link below needs the same,
# or it becomes a real directory and proves nothing.
case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/kept" "$repo/ai/skills/doomed" \
         "$repo/ai/agents" "$repo/ai/secrets" "$home/.claude/skills"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf -- '---\nname: kept\n---\n' > "$repo/ai/skills/kept/SKILL.md"
printf -- '---\nname: doomed\n---\n' > "$repo/ai/skills/doomed/SKILL.md"

# A link this script did not make, pointing outside the repo. It is dangling
# too, and it must survive: pruning is only ever allowed to undo its own work.
# Created against a real directory and orphaned afterwards, because on Git Bash
# `ln -s` refuses a target that does not exist yet.
mkdir -p "$work/somewhere-else"
ln -s "$work/somewhere-else" "$home/.claude/skills/foreign"
rmdir "$work/somewhere-else"

HOME="$home"; export HOME

install() { sh "$repo/ai/install.sh" --skills-only > /dev/null 2>&1; }
check()   { sh "$repo/ai/install.sh" --check --skills-only 2>&1; }

install
if [ -L "$home/.claude/skills/doomed" ]; then linked=y; else linked=n; fi
assert_eq "both skills link on a first install" "y" "$linked"

# The prune: a skill removed from the repo, as `git rm` would leave it.
rm -rf "$repo/ai/skills/doomed"

out="$(check)"; rc=$?
assert_eq "--check fails while a stale link is present" "1" "$rc"
case "$out" in *"skills/doomed"*) named=y ;; *) named=n ;; esac
assert_eq "--check names the stale link" "y" "$named"

install
if [ -L "$home/.claude/skills/doomed" ] || [ -e "$home/.claude/skills/doomed" ]; then gone=n; else gone=y; fi
assert_eq "install removes the stale link" "y" "$gone"

if [ -L "$home/.claude/skills/kept" ]; then still=y; else still=n; fi
assert_eq "install leaves the surviving skill linked" "y" "$still"

if [ -L "$home/.claude/skills/foreign" ]; then foreign=y; else foreign=n; fi
assert_eq "a dangling link into somewhere else is left alone" "y" "$foreign"

out="$(check)"; rc=$?
assert_eq "--check is clean once the stale link is gone" "0" "$rc"

assert_summary "install.sh orphan pruning"
