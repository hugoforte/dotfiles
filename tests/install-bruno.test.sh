#!/bin/sh

# Fixture suite for the Bruno component of ai/install.sh: the collections an overlay ships under
# <overlay>/bruno/, linked into ~/bruno, pruned when the overlay stops shipping one, and refused
# when an earlier overlay already ships the name.
#
# The overlays are the ones a fixture ai/secrets/machine.local.psd1 lists. No collection lives in
# this repo, so unlike the skills suites there is nothing of the repo's own to link beside them.

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
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$home" \
         "$first/bruno/account-takeover" "$first/bruno/doomed" "$second/bruno/other"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT/ai/helpers/output.sh" "$repo/ai/helpers/output.sh"
cp "$REPO_ROOT/ai/helpers/settings-reconcile.sh" "$repo/ai/helpers/settings-reconcile.sh"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
for coll in "$first/bruno/account-takeover" "$first/bruno/doomed" "$second/bruno/other"; do
    printf '{\n  "version": "1",\n  "name": "%s",\n  "type": "collection"\n}\n' "$(basename "$coll")" \
        > "$coll/bruno.json"
done

# machine.local.psd1 holds Windows paths on a real machine; install.sh converts them.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n        '%s'\n    )\n}\n" "$(win "$first")" "$(win "$second")" \
    > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

bruno() { sh "$repo/ai/install.sh" --bruno-only "$@" > /dev/null 2>&1; }
check() { sh "$repo/ai/install.sh" --check --bruno-only 2>&1; }
is_link() { if [ -L "$1" ]; then echo y; else echo n; fi; }

bruno; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "an overlay's collection links on install" "y" "$(is_link "$home/bruno/account-takeover")"
assert_eq "the link points into the overlay" "$first/bruno/account-takeover" "$(readlink "$home/bruno/account-takeover")"
assert_eq "every listed overlay's collections link" "y" "$(is_link "$home/bruno/other")"

out="$(check)"; rc=$?
assert_eq "--check is clean with everything linked" "0" "$rc"

# The overlay stops shipping a collection, as a pull of the private repo would leave it.
rm -rf "$first/bruno/doomed"

out="$(check)"; rc=$?
assert_eq "--check fails on the link the overlay left behind" "1" "$rc"
case "$out" in *"bruno/doomed"*) named=y ;; *) named=n ;; esac
assert_eq "--check names it" "y" "$named"

bruno
if [ -L "$home/bruno/doomed" ] || [ -e "$home/bruno/doomed" ]; then gone=n; else gone=y; fi
assert_eq "install prunes it" "y" "$gone"
assert_eq "and leaves the overlay's surviving collection linked" "y" "$(is_link "$home/bruno/account-takeover")"

# A name an earlier overlay already ships: the first one listed keeps it.
mkdir -p "$second/bruno/account-takeover"
printf '{\n  "type": "collection"\n}\n' > "$second/bruno/account-takeover/bruno.json"
out="$(sh "$repo/ai/install.sh" --bruno-only 2> /dev/null)"; rc=$?
assert_eq "install carries on past a name an earlier overlay ships" "0" "$rc"
case "$out" in *"$second/bruno/account-takeover not linked"*) named=y ;; *) named=n ;; esac
assert_eq "and says on stdout which collection it refused" "y" "$named"
assert_eq "and the earlier overlay keeps the name" "$first/bruno/account-takeover" "$(readlink "$home/bruno/account-takeover")"
out="$(check)"; rc=$?
assert_eq "--check fails on that clash" "1" "$rc"
rm -rf "$second/bruno/account-takeover"

# The same name in another case: one link on NTFS, so the same refusal.
mkdir -p "$second/bruno/Account-Takeover"
printf '{\n  "type": "collection"\n}\n' > "$second/bruno/Account-Takeover/bruno.json"
bruno
assert_eq "the earlier overlay keeps a name a later one ships in another case" "$first/bruno/account-takeover" "$(readlink "$home/bruno/account-takeover")"
out="$(check)"; rc=$?
assert_eq "--check fails on a clash in another case" "1" "$rc"
rm -rf "$second/bruno/Account-Takeover"

# Teardown undoes only what install did: a collection the overlay dropped since the last install
# leaves a stale link that --uninstall must take too, and a link someone pointed elsewhere at a
# name an overlay ships is theirs, not ours.
mkdir -p "$first/bruno/dropped" "$second/bruno/repointed" "$work/theirs"
printf '{
  "type": "collection"
}
' > "$first/bruno/dropped/bruno.json"
printf '{
  "type": "collection"
}
' > "$second/bruno/repointed/bruno.json"
bruno
rm -rf "$first/bruno/dropped"
rm -f "$home/bruno/repointed"
ln -s "$work/theirs" "$home/bruno/repointed"

bruno --uninstall
assert_eq "--uninstall removes the first overlay's links" "n" "$(is_link "$home/bruno/account-takeover")"
assert_eq "and the second overlay's" "n" "$(is_link "$home/bruno/other")"
assert_eq "and the stale link of a collection the overlay dropped" "n" "$(is_link "$home/bruno/dropped")"
assert_eq "but not a link someone pointed elsewhere at a managed name" "$work/theirs" "$(readlink "$home/bruno/repointed")"
rm -f "$home/bruno/repointed"

# A machine with no overlays: nothing linked, nothing drifted, and no empty ~/bruno created.
rm -f "$repo/ai/secrets/machine.local.psd1"
rm -rf "$home/bruno"
out="$(check)"; rc=$?
assert_eq "--check is clean on a machine without overlays" "0" "$rc"
bruno; rc=$?
assert_eq "install succeeds on a machine without overlays" "0" "$rc"
assert_eq "and creates no empty ~/bruno" "n" "$(if [ -d "$home/bruno" ]; then echo y; else echo n; fi)"

assert_summary "install.sh Bruno collections"
