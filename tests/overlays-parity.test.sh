#!/bin/sh

# The sh and PowerShell overlay readers agree: both are run on one fixture machine.local.psd1,
# registry and overlay tree, each walking its own table (tests/overlays-dump.sh and
# tests/Dump-Overlays.ps1), and what they read must be the same. A row, a count or a rule changed
# in one language alone fails it.
#
# Windows only, where Windows PowerShell 5.1 sits beside Git Bash, as on the Windows CI job. Paths
# are compared in C:/ form, with the fixture root replaced.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) echo "overlays parity: Windows only, where Windows PowerShell sits beside Git Bash; skipped"; exit 0 ;;
esac
command -v powershell.exe > /dev/null 2>&1 || { echo "  FAIL  powershell.exe not found, so the readers cannot be compared"; exit 1; }

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
first="$work/private/first"
second="$work/private/second"
file() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
registry() {
    file "$1/ai/secrets/registry.psd1" "@{
    Skills = @(
        @{
            Id     = '$2'
            Marker = '.claude/skills/$2'
            Remote = 'github.com/x/$2'
            Files  = @('.secrets.env', 'b.env')
        }
        @{
            Id    = '$2-shipped'
            Files = @('.env')
        }
    )
}"
}

# A source for every row of the table, a clash for each kind that can clash, and the repo where a
# row reads it.
file "$repo/ai/secrets/machine.local.psd1" "@{
    Overlays = @(
        '$(cygpath -w "$first")'
        '$(cygpath -w "$second")'
    )
}"
file "$second/aws/config"
file "$first/ssh/authorized_keys"
file "$second/ssh/authorized_keys"
file "$repo/ssh/authorized_keys"
file "$first/machines/BOX.psd1"
file "$first/machines/OTHER.psd1"
file "$second/machines/BOX.Brewfile"
file "$first/git/gitconfig"
file "$second/git/gitconfig"
file "$first/macos/Brewfile"
file "$second/macos/bootstrap.sh"
file "$second/ai/claude/config-dirs"
file "$first/machines/BOX.config-dirs"
file "$second/machines/BOX.config-dirs"
file "$repo/powershell/tools.psd1"
file "$first/powershell/tools.psd1"
registry "$repo" alpha
registry "$second" beta
mkdir -p "$repo/ai/skills/own" "$first/ai/skills/alpha" "$first/ai/skills/own" "$first/ai/skills/shared" \
         "$second/ai/skills/Shared" "$first/bruno/api" "$second/bruno/api" "$second/bruno/web"
file "$first/ai/rules/style.md"
file "$first/ai/rules/notes.txt"
file "$first/ai/rules/.draft.md"
mkdir -p "$first/ai/skills/.wip"
file "$second/ai/rules/Style.md"
file "$repo/ai/agents/reviewer.md"
file "$second/ai/agents/reviewer.md"
file "$second/ai/agents/planner.md"
git init -q "$work/private"

# swap <from> <to>: every <from> in stdin replaced by <to>, literally
swap() { awk -v from="$1" -v to="$2" '{ out = ""; while ((i = index($0, from)) > 0) { out = out substr($0, 1, i - 1) to; $0 = substr($0, i + length(from)) } print out $0 }'; }

COMPUTERNAME=box.example; export COMPUTERNAME
root="$(cygpath -m "$work")"
sh_dump="$(sh "$SCRIPT_DIR/overlays-dump.sh" "$repo" 2>&1 | swap "$work" "<ROOT>" | swap "$root" "<ROOT>")"
ps_dump="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SCRIPT_DIR/Dump-Overlays.ps1")" -RepoPath "$(cygpath -w "$repo")" 2>&1 |
    tr -d '\r' | tr '\\' '/' | swap "$root" "<ROOT>")"

TAB="$(printf '\t')"
case "$sh_dump" in *"bruno/*/$TAB<ROOT>/private/second/bruno/api$TAB<ROOT>/private/first/bruno/api"*"ai/agents/*.md$TAB<ROOT>/private/second/ai/agents/reviewer.md$TAB<ROOT>/repo/ai/agents/reviewer.md"*"skill${TAB}beta$TAB"*) whole=y ;; *) whole=n ;; esac
assert_eq "the sh dump reads the whole fixture, so agreeing is not agreeing on nothing" "y" "$whole"
assert_eq "both readers read the same overlays, key, repositories, sources, entries and skills" "$sh_dump" "$ps_dump"

assert_summary "overlays parity"
