#!/bin/sh

# Fixture suite for the rules and overlay agents ai/install.sh links: this repo's and each overlay's
# ai/rules/*.md into every Claude config folder's rules/, where Claude Code reads them beside
# CLAUDE.md, and an overlay's ai/agents/*.md beside this repo's agents. A name this repo or an
# earlier overlay already ships is refused, and a link to an entry that is no longer shipped is
# pruned.
#
# The overlays are the ones a fixture ai/secrets/machine.local.psd1 lists, the second naming an
# extra Claude config folder, and RIG_ROOT points at an empty directory.

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
mkdir -p "$repo/ai/helpers" "$repo/ai/agents" "$repo/ai/rules" "$repo/ai/skills" "$repo/ai/secrets" "$home" \
         "$first/ai/rules" "$first/ai/agents" "$second/ai/rules" "$second/ai/agents" "$second/ai/claude"

cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\npaths: ["**/*.md"]\n---\n' > "$repo/ai/rules/markdown.md"
printf '# retired\n' > "$repo/ai/rules/retired.md"
printf '# style\n' > "$first/ai/rules/style.md"
printf '# doomed\n' > "$first/ai/rules/doomed.md"
printf 'not a rule\n' > "$first/ai/rules/notes.txt"
printf -- '---\nname: planner\n---\n' > "$first/ai/agents/planner.md"
printf '# team\n' > "$second/ai/rules/team.md"
printf '# theirs\n' > "$second/ai/rules/markdown.md"
printf -- '---\nname: helper\n---\n' > "$second/ai/agents/helper.md"
printf '~/.claude-extra\n' > "$second/ai/claude/config-dirs"

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    Overlays = @(\n        '%s'\n        '%s'\n    )\n}\n" "$(win "$first")" "$(win "$second")" \
    > "$repo/ai/secrets/machine.local.psd1"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT

run()     { sh "$repo/ai/install.sh" --agents-only "$@" > /dev/null 2>&1; sh "$repo/ai/install.sh" --rules-only "$@" > /dev/null 2>&1; }
check()   { sh "$repo/ai/install.sh" --check --agents-only 2>&1; sh "$repo/ai/install.sh" --check --rules-only 2>&1; }
checkrc() { sh "$repo/ai/install.sh" --check --agents-only > /dev/null 2>&1 && sh "$repo/ai/install.sh" --check --rules-only > /dev/null 2>&1; echo $?; }
is_link() { if [ -L "$1" ]; then echo y; else echo n; fi; }
says()    { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }

run
assert_eq "an overlay's rule is linked into ~/.claude/rules" "$first/ai/rules/style.md" "$(readlink "$home/.claude/rules/style.md")"
assert_eq "every overlay's rules are" "y" "$(is_link "$home/.claude/rules/team.md")"
assert_eq "and into an extra Claude config folder's rules" "y" "$(is_link "$home/.claude-extra/rules/style.md")"
assert_eq "a file that is not .md is no rule" "n" "$(is_link "$home/.claude/rules/notes.txt")"
assert_eq "this repo's rule is linked into ~/.claude/rules" "$repo/ai/rules/markdown.md" "$(readlink "$home/.claude/rules/markdown.md")"
assert_eq "and into an extra Claude config folder's rules" "$repo/ai/rules/markdown.md" "$(readlink "$home/.claude-extra/rules/markdown.md")"
assert_eq "an overlay's agent is linked beside this repo's" "$first/ai/agents/planner.md" "$(readlink "$home/.claude/agents/planner.md")"
assert_eq "an agent name this repo ships keeps this repo's link" "$repo/ai/agents/helper.md" "$(readlink "$home/.claude/agents/helper.md")"

out="$(check)"
assert_eq "--check fails on the agent name this repo already ships" "1" "$(checkrc)"
assert_eq "and names the refused agent" "y" "$(says "$out" "$second/ai/agents/helper.md not linked")"
assert_eq "and names the refused rule" "y" "$(says "$out" "$second/ai/rules/markdown.md not linked")"
rm "$second/ai/agents/helper.md" "$second/ai/rules/markdown.md"
assert_eq "--check is clean once the clashes are gone" "0" "$(checkrc)"

# This repo stops shipping a rule, as a pull of this repo would leave it.
rm "$repo/ai/rules/retired.md"
assert_eq "--check fails on this repo's rule link left behind" "1" "$(checkrc)"
run
assert_eq "install prunes it" "n" "$(is_link "$home/.claude/rules/retired.md")"
assert_eq "and leaves this repo's surviving rule" "y" "$(is_link "$home/.claude/rules/markdown.md")"

# The overlay stops shipping a rule, as a pull of the private repo would leave it.
rm "$first/ai/rules/doomed.md"
assert_eq "--check fails on the rule link left behind" "1" "$(checkrc)"
run
assert_eq "install prunes it" "n" "$(is_link "$home/.claude/rules/doomed.md")"
assert_eq "and leaves the surviving rule" "y" "$(is_link "$home/.claude/rules/style.md")"

run --uninstall
assert_eq "--uninstall removes the rule links" "n" "$(is_link "$home/.claude/rules/style.md")"
assert_eq "this repo's included" "n" "$(is_link "$home/.claude/rules/markdown.md")"
assert_eq "and the overlay agent links" "n" "$(is_link "$home/.claude/agents/planner.md")"
assert_eq "and this repo's agent links, as before" "n" "$(is_link "$home/.claude/agents/helper.md")"

assert_summary "install.sh rules and overlay agents"
