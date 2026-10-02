#!/bin/sh

# Fixture suite for the overlay-skills component of ai/install.sh: the skills an
# overlay ships under <overlay>/ai/skills/, linked into the agents' skills
# directories beside this repo's own, pruned when the overlay stops shipping
# one, and refused when another source already ships the name.
#
# The overlays are the ones a fixture ai/secrets/machine.local.psd1 lists, and
# RIG_ROOT points at an empty directory so the real rig checkout stays out of it.

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
first="$work/private/first"
second="$work/private/second"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/own" "$repo/ai/agents" "$repo/ai/secrets" \
         "$home/.claude/skills" "$first/ai/skills/private-thing" "$first/ai/skills/doomed" \
         "$second/ai/skills/other"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
for skill in "$repo/ai/skills/own" "$first/ai/skills/private-thing" "$first/ai/skills/doomed" \
             "$second/ai/skills/other"; do
    printf -- '---\nname: %s\n---\n' "$(basename "$skill")" > "$skill/SKILL.md"
done

# machine.local.psd1 holds Windows paths on a real machine; install.sh converts them.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n        '%s'\n    )\n}\n" "$(win "$first")" "$(win "$second")" \
    > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

own()      { sh "$repo/ai/install.sh" --skills-only > /dev/null 2>&1; }
overlays() { sh "$repo/ai/install.sh" --overlay-skills-only "$@" > /dev/null 2>&1; }
check()    { sh "$repo/ai/install.sh" --check --overlay-skills-only 2>&1; }
is_link()  { if [ -L "$1" ]; then echo y; else echo n; fi; }

own
overlays; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "an overlay's skill links on install" "y" "$(is_link "$home/.claude/skills/private-thing")"
assert_eq "the link points into the overlay" "$first/ai/skills/private-thing" "$(readlink "$home/.claude/skills/private-thing")"
assert_eq "every listed overlay's skills link" "y" "$(is_link "$home/.claude/skills/other")"
assert_eq "this repo's own skill links beside them" "y" "$(is_link "$home/.claude/skills/own")"

out="$(check)"; rc=$?
assert_eq "--check is clean with everything linked" "0" "$rc"

# The overlay stops shipping a skill, as a pull of the private repo would leave it.
rm -rf "$first/ai/skills/doomed"

out="$(check)"; rc=$?
assert_eq "--check fails on the link the overlay left behind" "1" "$rc"
case "$out" in *"skills/doomed"*) named=y ;; *) named=n ;; esac
assert_eq "--check names it" "y" "$named"

overlays
if [ -L "$home/.claude/skills/doomed" ] || [ -e "$home/.claude/skills/doomed" ]; then gone=n; else gone=y; fi
assert_eq "install prunes it" "y" "$gone"
assert_eq "and leaves the overlay's surviving skill linked" "y" "$(is_link "$home/.claude/skills/private-thing")"
assert_eq "and leaves this repo's skill alone" "y" "$(is_link "$home/.claude/skills/own")"

# A name this repo already ships: refused, and the repo's link left in place.
mkdir -p "$second/ai/skills/own" "$second/ai/skills/late"
printf -- '---\nname: own\n---\n' > "$second/ai/skills/own/SKILL.md"
printf -- '---\nname: late\n---\n' > "$second/ai/skills/late/SKILL.md"

# Install warns rather than failing, so a clash cannot stop the sync that runs it; the warning
# goes to stdout, the stream sync.ps1 can log. --check is what fails.
out="$(sh "$repo/ai/install.sh" --overlay-skills-only 2> /dev/null)"; rc=$?
assert_eq "install carries on past a name this repo already ships" "0" "$rc"
case "$out" in *"$second/ai/skills/own not linked"*) named=y ;; *) named=n ;; esac
assert_eq "and says on stdout which skill it refused" "y" "$named"
assert_eq "and leaves this repo's link where it points" "$repo/ai/skills/own" "$(readlink "$home/.claude/skills/own")"
assert_eq "and still links the overlay's other new skills" "y" "$(is_link "$home/.claude/skills/late")"
out="$(check)"; rc=$?
assert_eq "--check fails on it" "1" "$rc"
case "$out" in *"$second/ai/skills/own"*) named=y ;; *) named=n ;; esac
assert_eq "--check names the refused skill" "y" "$named"
rm -rf "$second/ai/skills/own"

# A name an earlier overlay already ships: the first one listed keeps it.
mkdir -p "$second/ai/skills/private-thing"
printf -- '---\nname: private-thing\n---\n' > "$second/ai/skills/private-thing/SKILL.md"

overlays
assert_eq "an earlier overlay keeps a name a later one also ships" "$first/ai/skills/private-thing" "$(readlink "$home/.claude/skills/private-thing")"
out="$(check)"; rc=$?
assert_eq "--check fails on that clash" "1" "$rc"
rm -rf "$second/ai/skills/private-thing"

# The same name in another case: one link on NTFS, so the same refusal.
mkdir -p "$second/ai/skills/Private-Thing"
printf -- '---\nname: Private-Thing\n---\n' > "$second/ai/skills/Private-Thing/SKILL.md"
overlays
assert_eq "the earlier overlay keeps a name a later one ships in another case" "$first/ai/skills/private-thing" "$(readlink "$home/.claude/skills/private-thing")"
out="$(check)"; rc=$?
assert_eq "--check fails on a clash in another case" "1" "$rc"
rm -rf "$second/ai/skills/Private-Thing"

# A name rig already ships.
rig="$work/rig"
mkdir -p "$rig/bin" "$rig/skills/rigged" "$second/ai/skills/rigged"
: > "$rig/bin/rig.mjs"
printf -- '---\nname: rigged\n---\n' > "$rig/skills/rigged/SKILL.md"
printf -- '---\nname: rigged\n---\n' > "$second/ai/skills/rigged/SKILL.md"
RIG_ROOT="$rig"; export RIG_ROOT
overlays
assert_eq "a name rig already ships is not linked from an overlay" "n" "$(is_link "$home/.claude/skills/rigged")"
out="$(check)"; rc=$?
assert_eq "--check fails on a name rig already ships" "1" "$rc"
rm -rf "$second/ai/skills/rigged"
RIG_ROOT="$work/no-rig"; export RIG_ROOT

# A link someone pointed elsewhere at a name an overlay ships is theirs, and a skill the overlay
# dropped since the last install leaves a stale link teardown must take too.
mkdir -p "$first/ai/skills/dropped" "$first/ai/skills/shared" "$work/theirs"
printf -- '---\nname: dropped\n---\n' > "$first/ai/skills/dropped/SKILL.md"
printf -- '---\nname: shared\n---\n' > "$first/ai/skills/shared/SKILL.md"
overlays
rm -rf "$first/ai/skills/dropped"
rm -f "$home/.claude/skills/late"
ln -s "$work/theirs" "$home/.claude/skills/late"

# A name both overlays ship, linked from the first and then the order swapped: the link install
# made now belongs to the refused entry, and is still install's to take.
mkdir -p "$second/ai/skills/shared"
printf -- '---\nname: shared\n---\n' > "$second/ai/skills/shared/SKILL.md"
printf "@{\n    Overlays = @(\n        '%s'\n        '%s'\n    )\n}\n" "$(win "$second")" "$(win "$first")" \
    > "$repo/ai/secrets/machine.local.psd1"

overlays --uninstall
assert_eq "--uninstall removes the first overlay's links" "n" "$(is_link "$home/.claude/skills/private-thing")"
assert_eq "and the second overlay's" "n" "$(is_link "$home/.claude/skills/other")"
assert_eq "and not this repo's" "y" "$(is_link "$home/.claude/skills/own")"
assert_eq "and the stale link of a skill the overlay dropped" "n" "$(is_link "$home/.claude/skills/dropped")"
assert_eq "and a link install made to a name now refused as a clash" "n" "$(is_link "$home/.claude/skills/shared")"
rm -rf "$second/ai/skills/shared"
assert_eq "but not a link someone pointed elsewhere at a managed name" "$work/theirs" "$(readlink "$home/.claude/skills/late")"
rm -f "$home/.claude/skills/late"

# An overlay listed with a trailing separator, which the PowerShell reader accepts.
printf "@{\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$first")\\" > "$repo/ai/secrets/machine.local.psd1"
overlays
assert_eq "a trailing separator still gives the overlay's own path" "$first/ai/skills/private-thing" "$(readlink "$home/.claude/skills/private-thing")"
out="$(check)"; rc=$?
assert_eq "--check is clean with a trailing separator" "0" "$rc"
mkdir -p "$first/ai/skills/brief"
printf -- '---\nname: brief\n---\n' > "$first/ai/skills/brief/SKILL.md"
overlays
rm -rf "$first/ai/skills/brief"
overlays
assert_eq "and the prune still finds a dropped skill's link" "n" "$(is_link "$home/.claude/skills/brief")"

# A machine with no overlays: nothing linked, nothing drifted.
rm -f "$repo/ai/secrets/machine.local.psd1"
out="$(check)"; rc=$?
assert_eq "--check is clean on a machine without overlays" "0" "$rc"
overlays; rc=$?
assert_eq "install succeeds on a machine without overlays" "0" "$rc"

assert_summary "install.sh overlay skills"
