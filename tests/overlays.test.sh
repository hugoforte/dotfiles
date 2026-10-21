#!/bin/sh

# Fixture suite for ai/helpers/overlays.sh, the overlay rules in sh: which overlays a machine
# lists, the one source or every source of a path, the entries under a directory, the machine key,
# the overlay repositories, and the merged skill registry. Each rule is asked through the module's
# interface, in a fresh sh, so nothing it sets leaks between assertions.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
first="$work/private/first"
second="$work/private/second"
stubs="$work/stubs"
mkdir -p "$repo/ai/secrets" "$first" "$second" "$stubs"

# The key comes from COMPUTERNAME alone: scutil, which a Mac would ask next, names nothing.
printf '#!/bin/sh\nexit 1\n' > "$stubs/scutil"
chmod +x "$stubs/scutil"
PATH="$stubs:$PATH"; export PATH

# machine.local.psd1 holds Windows paths on a Windows machine, so on Git Bash write them that way.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
# list <dir>...: list these overlays in the fixture repo's machine.local.psd1
list() {
    {
        printf '@{\n    Overlays = @(\n'
        for dir in "$@"; do printf "        '%s'\n" "$(win "$dir")"; done
        printf '    )\n}\n'
    } > "$repo/ai/secrets/machine.local.psd1"
}
file() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2:-x}" > "$1"; }
# in_sh <script> [arg]...: run a script against the module in a fresh sh, loaded from the fixture
# repo's list unless the script loads it itself. $R is the fixture repo.
in_sh() {
    script="$1"; shift
    R="$repo" COMPUTERNAME="${KEY_NAME-box}" sh -c ". '$REPO_ROOT/ai/helpers/overlays.sh'; $script" _ "$@" 2>&1
}
loaded() { in_sh "overlays_load \"\$R\" > /dev/null || exit 1; $1"; }
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }

# --- which overlays -------------------------------------------------------------------------------

rm -f "$repo/ai/secrets/machine.local.psd1"
out="$(loaded 'printf "[%s]" "$OVERLAYS"')"
assert_eq "no machine.local.psd1 lists no overlays" "[]" "$out"

list "$first" "$second"
assert_eq "the listed overlays, in order" "$first
$second" "$(loaded 'printf "%s" "$OVERLAYS"')"

list "$first" "$work/gone"
out="$(in_sh 'overlays_load "$R"; echo "rc=$?"')"
assert_eq "a listed overlay that does not exist fails the load" "y" "$(says "$out" "rc=1")"
assert_eq "naming its path" "y" "$(says "$out" "$work/gone")"

list "$work/gone"
out="$(in_sh 'overlays_load "$R" "$1" "$2"; printf "rc=%s [%s]" "$?" "$OVERLAYS"' "$second" "$first")"
assert_eq "overlays passed as arguments replace the file's list" "rc=0 [$second
$first]" "$out"

out="$(in_sh 'overlays_load "$R" "$1"; echo "rc=$?"' "$work/also-gone")"
assert_eq "and are checked the same way" "y" "$(says "$out" "rc=1")"

if command -v cygpath > /dev/null 2>&1; then separator='\'; else separator='/'; fi
printf "@{ Overlays = @('%s%s') }\n" "$(win "$first")" "$separator" > "$repo/ai/secrets/machine.local.psd1"
assert_eq "a trailing separator is dropped" "$first" "$(loaded 'printf "%s" "$OVERLAYS"')"

# --- the machine key ------------------------------------------------------------------------------

list "$first"
assert_eq "the machine key is the name uppercased, up to its first dot" "BOX" "$(KEY_NAME=box.example.com loaded 'printf "%s" "$OVERLAY_KEY"')"

# --- the one source of a path ---------------------------------------------------------------------

list "$first" "$second"
assert_eq "a one path no root ships has no source" "" "$(loaded 'overlay_sources aws/config')"

file "$second/aws/config"
assert_eq "a one path has the source that ships it" "$second/aws/config" "$(loaded 'overlay_sources aws/config')"

file "$repo/aws/config"
out="$(loaded 'overlay_sources aws/config; echo "rc=$?"')"
assert_eq "two sources of a one path fail" "y" "$(says "$out" "rc=1")"
assert_eq "naming both" "y" "$(says "$out" "$repo/aws/config and $second/aws/config")"
rm -f "$repo/aws/config" "$second/aws/config"

file "$repo/ssh/authorized_keys"
assert_eq "a path read from the overlays alone ignores the repo" "" "$(loaded 'overlay_sources ssh/authorized_keys')"
rm -rf "$repo/ssh"

file "$first/machines/BOX.psd1"
file "$first/machines/OTHER.psd1"
assert_eq "{KEY} in a path is the machine key" "$first/machines/BOX.psd1" "$(KEY_NAME=box loaded 'overlay_sources "machines/{KEY}.psd1"')"
assert_eq "and with no key the path matches nothing" "" "$(KEY_NAME='' loaded 'overlay_sources "machines/{KEY}.psd1"')"

# --- every source of a path -----------------------------------------------------------------------

file "$second/machines"
assert_eq "a path ending in / has each overlay's folder there, and not a file" "$first/machines" "$(loaded 'overlay_sources machines/')"
rm -f "$second/machines"

file "$second/git/gitconfig"
file "$first/git/gitconfig"
assert_eq "an all path has every source, in overlay order" "$first/git/gitconfig
$second/git/gitconfig" "$(loaded 'overlay_sources git/gitconfig')"

file "$repo/powershell/tools.psd1"
file "$second/powershell/tools.psd1"
assert_eq "a path read from the repo and the overlays has the repo first" "$repo/powershell/tools.psd1
$second/powershell/tools.psd1" "$(loaded 'overlay_sources powershell/tools.psd1')"

# --- what the interface refuses -------------------------------------------------------------------

out="$(loaded 'overlay_sources not/a/rule; echo "rc=$?"')"
assert_eq "a path not in the table is an error" "y" "$(says "$out" "rc=1")"
out="$(in_sh 'overlay_sources aws/config; echo "rc=$?"')"
assert_eq "asking for sources before the overlays are loaded returns 2" "y" "$(says "$out" "rc=2")"
out="$(loaded 'overlay_sources ai/skills; echo "rc=$?"')"
assert_eq "a directory of entries has no sources of its own" "y" "$(says "$out" "rc=1")"

# --- the entries under a directory ----------------------------------------------------------------

# Names whose order no locale disputes: within an overlay the order is only the listing's.
mkdir -p "$first/ai/skills/alpha" "$first/ai/skills/own" "$first/ai/skills/shared" \
         "$second/ai/skills/Shared" "$repo/ai/skills/own"
file "$first/ai/skills/README.md"
TAB="$(printf '\t')"
assert_eq "each entry in overlay order, an earlier overlay keeping a name without case, a claimant before them" \
    "$first/ai/skills/alpha$TAB
$first/ai/skills/own$TAB$repo/ai/skills/own
$first/ai/skills/shared$TAB
$second/ai/skills/Shared$TAB$first/ai/skills/shared" \
    "$(loaded 'overlay_entries ai/skills "$R/ai/skills"')"

# --- the overlay repositories ---------------------------------------------------------------------

git init -q "$work/private"
out="$(loaded 'printf "%s" "$OVERLAY_REPOS"')"
expected="$(git -C "$first" rev-parse --show-toplevel)"
assert_eq "a repository holding two overlays is listed once" "$expected" "$out"

# --- the merged skill registry --------------------------------------------------------------------

registry() {
    file "$1/ai/secrets/registry.psd1" "@{
    Skills = @(
        @{
            Id     = '$2'
            Marker = '.claude/skills/$2'
            Remote = 'github.com/x/$2'
            Files  = @('.secrets.env', 'b.env')
        }
    )
}"
}
registry "$repo" alpha
registry "$second" beta
FS="$(printf '\037')"
assert_eq "every registry's skills, the repo's first, each with its registry" \
    "alpha$FS.claude/skills/alpha${FS}github.com/x/alpha$FS.secrets.env b.env$FS$repo/ai/secrets/registry.psd1
beta$FS.claude/skills/beta${FS}github.com/x/beta$FS.secrets.env b.env$FS$second/ai/secrets/registry.psd1" \
    "$(loaded 'merged_skill_registry')"

registry "$first" beta
out="$(loaded 'merged_skill_registry; echo "rc=$?"')"
assert_eq "an Id registered twice fails" "y" "$(says "$out" "rc=1")"
assert_eq "naming both registries" "y" "$(says "$out" "$first/ai/secrets/registry.psd1 and $second/ai/secrets/registry.psd1")"

registry "$first" Beta
out="$(loaded 'merged_skill_registry; echo "rc=$?"')"
assert_eq "an Id registered twice in another case fails, as PowerShell's does" "y" "$(says "$out" "rc=1")"

file "$first/ai/secrets/registry.psd1" "@{ Skills = @( @{ Id = 'odd'; Files = 'not-a-list' } ) }"
out="$(loaded 'merged_skill_registry; echo "rc=$?"')"
assert_eq "an entry it cannot read fails, naming the registry" "y" "$(says "$out" "$first/ai/secrets/registry.psd1 has an entry this cannot read")"

# --- the list in the README -----------------------------------------------------------------------

# Every path in the table is in README's list of what an overlay may hold, so the list cannot fall
# behind the code. {KEY} is written <KEY> there, and a directory of entries ends in /.
section="$(awk '/^## Private configuration: overlays/ { on = 1; next } on && /^## / { exit } on' "$REPO_ROOT/README.md")"
missing="$(in_sh 'printf "%s\n" "$OVERLAY_RULES"' | while read -r path count roots; do
    shown="$(printf '%s' "$path" | sed 's/{KEY}/<KEY>/')"
    [ "$count" = "entries" ] && shown="$shown/"
    printf '%s\n' "$section" | grep -qF -- "- \`$shown" || printf '%s ' "$path"
done)"
assert_eq "README lists every path in the table" "" "$missing"

assert_summary "overlays.sh"
