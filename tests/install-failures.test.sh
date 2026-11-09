#!/bin/sh

# Fixture suite for how ai/install.sh reports a step that failed: an install that could not link
# something, merge the settings or read its own here-documents (a full disk makes each of them fail)
# exits non-zero, says the install had failures, and does not print "Done". The failures are made
# with an unwritable directory, a settings fragment that is not JSON and a file size limit of zero.
# The first and last are skipped where they cannot fail: root writes anywhere, and a shell that keeps
# here-documents in memory (bash 5.1 and later) has none to fail.
#
# HOME has a space in it and RIG_ROOT points at an empty directory, as in install-claude-dirs.test.sh.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'chmod -R u+rwx "$work" 2> /dev/null; rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home dir"
cwd="$work/cwd"
mkdir -p "$repo/ai/helpers" "$repo/ai/skills/own" "$repo/ai/agents" "$repo/ai/claude" "$repo/ai/secrets" \
         "$home" "$cwd"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"
printf "@{\n    Overlays = @(\n    )\n}\n" > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

run()   { (cd "$cwd" && sh "$repo/ai/install.sh" "$@" --no-rig-skills --no-overlay-skills --no-bruno 2>&1); }
says()  { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
fresh() { chmod -R u+rwx "$home" 2> /dev/null; rm -rf "$home" "$cwd"; mkdir -p "$home" "$cwd"; }

out="$(run)"; rc=$?
assert_eq "a clean install succeeds" "0" "$rc"
assert_eq "and says Done" "y" "$(says "$out" "Done")"

# A link that cannot be made: ~/.claude/agents exists and cannot be written into.
fresh
mkdir -p "$home/.claude/agents"
chmod 500 "$home/.claude/agents"
if [ -w "$home/.claude/agents" ]; then
    echo "  SKIP  an unwritable agents directory cannot be made here"
else
    out="$(run)"; rc=$?
    assert_eq "an install that could not link an agent fails" "1" "$rc"
    assert_eq "it says the install had failures" "y" "$(says "$out" "Install finished with failures")"
    assert_eq "it does not say Done" "n" "$(says "$out" "Done")"
    assert_eq "it still links what it can: the skills" "y" "$([ -L "$home/.claude/skills/own" ] && echo y || echo n)"
fi
chmod 700 "$home/.claude/agents"

# A settings merge that fails: a fragment that is not JSON.
if command -v jq > /dev/null 2>&1; then
    fresh
    printf '{ not json\n' > "$repo/ai/claude/settings.json"
    out="$(run)"; rc=$?
    assert_eq "an install whose settings merge failed fails" "1" "$rc"
    assert_eq "it says the install had failures" "y" "$(says "$out" "Install finished with failures")"
    assert_eq "it does not say Done" "n" "$(says "$out" "Done")"
    printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"
fi

# A here-document that cannot be created: bash keeps it in a temp file, which a file size limit of
# zero (with the SIGXFSZ it raises ignored) makes fail the way a full disk does:
# "cannot create temp file for here document".
fresh
no_files() { (ulimit -f 0 && trap '' XFSZ && "$@"); }
probe="$(no_files sh -c 'cat <<EOF > /dev/null
x
EOF' 2>&1)"
if [ -z "$probe" ]; then
    echo "  SKIP  this shell's here-documents do not fail with a file size limit of zero"
else
    out="$(no_files run)"; rc=$?
    assert_eq "an install whose here-documents cannot be created fails" "1" "$rc"
    assert_eq "it says the install had failures" "y" "$(says "$out" "Install finished with failures")"
    assert_eq "it does not say Done" "n" "$(says "$out" "Done")"
fi

assert_summary "ai/install.sh failures"
