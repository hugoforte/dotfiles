#!/bin/sh

# Fixture suite for macos/deploy-secrets.sh: it reads the registries of the repo and every
# overlay, decrypts each skill's files into ~/.agent-secrets, and links a project skill's files
# into every checkout under a search root whose origin matches; --check reports and changes
# nothing. powershell/deploy-secrets.ps1 is the same contract on Windows.
#
# sops is a stub on PATH that "decrypts" by dropping an ENC: prefix, and fails on a file that says
# UNDECRYPTABLE. The checkouts are real git repositories with an origin.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS ;;
esac

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

repo="$work/repo"
home="$work/home dir"
stubs="$work/stubs"
personal="$work/private/personal"
src="$work/src"
mkdir -p "$repo/ai/helpers" "$repo/ai/secrets" "$repo/macos" "$home" "$stubs" \
         "$personal/ai/secrets/hf-tool" "$personal/ai/secrets/db-query" "$src"

cp "$REPO_ROOT/macos/deploy-secrets.sh" "$repo/macos/"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"

# A shipped skill (no Marker) and a project skill, one key a line as the real registries are.
cat > "$personal/ai/secrets/registry.psd1" <<'EOF'
# Managed skill secrets.
@{
    Skills = @(
        @{
            Id     = 'hf-tool'
            Files  = @('.secrets.env')
        }
        @{
            Id     = 'db-query'
            Marker = '.claude/skills/db-query'
            Remote = 'example/app'
            Files  = @('.secrets.env', 'keys.local.json')
        }
    )
}
EOF
printf 'ENC:TOKEN=shipped\n' > "$personal/ai/secrets/hf-tool/.secrets.env"
printf 'ENC:DB=secret\n' > "$personal/ai/secrets/db-query/.secrets.env"
printf 'ENC:{"key":1}\n' > "$personal/ai/secrets/db-query/keys.local.json"

win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
printf "@{\n    SearchRoots = @('%s')\n    Overlays = @(\n        '%s'\n    )\n}\n" \
    "$(win "$src")" "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"

# checkout <name> <origin> [marker]: a git repository under the search root
checkout() {
    git init -q "$src/$1"
    git -C "$src/$1" remote add origin "$2"
    [ -z "$3" ] || mkdir -p "$src/$1/$3"
}
checkout app "https://github.com/example/app.git" ".claude/skills/db-query"
checkout plain "https://github.com/example/plain.git"

printf '#!/bin/sh\n# sops decrypt --output <out> <in>\n[ "$1" = decrypt ] && [ "$2" = --output ] || exit 2\ngrep -q UNDECRYPTABLE "$4" && exit 1\nsed "s/^ENC://" "$4" > "$3"\n' > "$stubs/sops"
chmod +x "$stubs/sops"

HOME="$home"; export HOME
PATH="$stubs:$PATH"; export PATH

run()    { (cd "$work" && sh "$repo/macos/deploy-secrets.sh" "$@" 2>&1); }
check()  { run --check; }
says()   { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
exists() { if [ -e "$1" ] || [ -L "$1" ]; then echo y; else echo n; fi; }

secrets="$home/.agent-secrets"
marker="$src/app/.claude/skills/db-query"

# --- deploy ----------------------------------------------------------------------------------

printf 'DB=hand-copied\n' > "$marker/.secrets.env"
out="$(run)"; rc=$?
assert_eq "deploy succeeds" "0" "$rc"
assert_eq "a shipped skill's file is decrypted into ~/.agent-secrets" "TOKEN=shipped" "$(cat "$secrets/hf-tool/.secrets.env")"
assert_eq "a project skill's file is decrypted there too" "DB=secret" "$(cat "$secrets/db-query/.secrets.env")"
assert_eq "it is linked into the checkout whose origin matches" "$secrets/db-query/.secrets.env" "$(readlink "$marker/.secrets.env")"
assert_eq "every file of the skill is linked" "$secrets/db-query/keys.local.json" "$(readlink "$marker/keys.local.json")"
set -- "$secrets/backups/app/db-query"/.secrets.env.backup.*
assert_eq "the plaintext it displaced is backed up outside the checkout" "DB=hand-copied" "$(cat "$1")"
assert_eq "and nothing is left beside the link" "n" "$(exists "$(printf '%s' "$marker"/.secrets.env.backup.*)")"
assert_eq "a checkout without the marker gets nothing" "" "$(ls -A "$src/plain" | grep -v '^\.git$')"
mode="$(ls -l "$secrets/db-query/.secrets.env" | cut -c2-10)"
case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) assert_eq "decrypted files are readable by their owner alone" "rw-------" "$mode" ;;
esac

out="$(run)"; rc=$?
assert_eq "a second deploy succeeds" "0" "$rc"
assert_eq "and changes nothing" "n" "$(says "$out" "decrypted")"

# --- check -----------------------------------------------------------------------------------

out="$(check)"; rc=$?
assert_eq "--check is clean once deployed" "0" "$rc"

printf 'ENC:DB=rotated\n' > "$personal/ai/secrets/db-query/.secrets.env"
out="$(check)"; rc=$?
assert_eq "--check fails on a secret that changed" "1" "$rc"
assert_eq "--check says it would be updated" "y" "$(says "$out" "db-query/.secrets.env would be updated")"
assert_eq "--check leaves the old value in place" "DB=secret" "$(cat "$secrets/db-query/.secrets.env")"
run > /dev/null
assert_eq "deploy takes the new value" "DB=rotated" "$(cat "$marker/.secrets.env")"

rm "$marker/keys.local.json"
out="$(check)"; rc=$?
assert_eq "--check fails on a missing link" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" "app/.claude/skills/db-query/keys.local.json: missing")"
assert_eq "--check does not make it" "n" "$(exists "$marker/keys.local.json")"
run > /dev/null

# --- problems deploying will not fix ---------------------------------------------------------

printf 'ENC:UNDECRYPTABLE\n' > "$personal/ai/secrets/db-query/.secrets.env"
out="$(run)"; rc=$?
assert_eq "a failed decrypt fails the run" "1" "$rc"
assert_eq "and says to check the recipients" "y" "$(says "$out" "is this machine a recipient")"
assert_eq "and leaves the previous copy" "DB=rotated" "$(cat "$secrets/db-query/.secrets.env")"
printf 'ENC:DB=rotated\n' > "$personal/ai/secrets/db-query/.secrets.env"

checkout impostor "https://github.com/someone-else/app.git" ".claude/skills/db-query"
out="$(run)"; rc=$?
assert_eq "a checkout with the marker and another origin fails the run" "1" "$rc"
assert_eq "and is named" "y" "$(says "$out" "impostor: has db-query but origin")"
assert_eq "and gets nothing" "n" "$(exists "$src/impostor/.claude/skills/db-query/.secrets.env")"
rm -rf "$src/impostor"

mkdir -p "$repo/ai/secrets/db-query"
printf "@{\n    Skills = @(\n        @{\n            Id = 'db-query'\n            Files = @('.secrets.env')\n        }\n    )\n}\n" > "$repo/ai/secrets/registry.psd1"
out="$(run)"; rc=$?
assert_eq "a skill registered twice fails" "1" "$rc"
assert_eq "and names both registries" "y" "$(says "$out" "$repo/ai/secrets/registry.psd1")"
rm -r "$repo/ai/secrets/registry.psd1" "$repo/ai/secrets/db-query"

printf "@{\n    Skills = @(\n        @{ Id = 'one-line'; Files = @(\n            'a.env')\n        }\n    )\n}\n" > "$repo/ai/secrets/registry.psd1"
out="$(run)"; rc=$?
assert_eq "an entry it cannot read fails rather than being skipped" "1" "$rc"
assert_eq "and names the registry" "y" "$(says "$out" "$repo/ai/secrets/registry.psd1")"
rm "$repo/ai/secrets/registry.psd1"

# --- registries as PowerShell reads them -----------------------------------------------------

# A registry the repo itself carries, for one project skill, in the spelling under test.
# registry <Remote line>: write it with that Remote line, deploy, and leave the output in $out
mkdir -p "$repo/ai/secrets/cs"
printf 'ENC:CS=1\n' > "$repo/ai/secrets/cs/.secrets.env"
checkout tool "https://github.com/example/tool.git" ".claude/skills/cs"
checkout fork "https://github.com/attacker/fork.git" ".claude/skills/cs"
registry() {
    printf "@{\n    Skills = @(\n        @{\n            Id     = 'cs'\n            Marker = '.claude/skills/cs'\n            %s\n            Files  = @('.secrets.env')\n        }\n    )\n}\n" "$1" > "$repo/ai/secrets/registry.psd1"
    rm -f "$src/tool/.claude/skills/cs/.secrets.env" "$src/fork/.claude/skills/cs/.secrets.env"
    out="$(run)"; rc=$?
}

registry 'Remote = "example/tool"'
assert_eq "a double-quoted Remote is read: the matching checkout is linked" "y" "$(exists "$src/tool/.claude/skills/cs/.secrets.env")"
assert_eq "and a checkout of another origin is not" "n" "$(exists "$src/fork/.claude/skills/cs/.secrets.env")"
registry "remote = 'example/tool'"
assert_eq "a key in another case is read: a checkout of another origin is not linked" "n" "$(exists "$src/fork/.claude/skills/cs/.secrets.env")"
registry "Remote = 'Example/Tool'"
assert_eq "an origin matches its Remote without case, as on Windows" "y" "$(exists "$src/tool/.claude/skills/cs/.secrets.env")"
registry ""
assert_eq "a Marker with no Remote fails rather than matching every origin" "1" "$rc"
assert_eq "and links nothing" "n" "$(exists "$src/fork/.claude/skills/cs/.secrets.env")"
registry 'Remote = example/tool'
assert_eq "a value it cannot read fails the run" "1" "$rc"
assert_eq "and names the registry" "y" "$(says "$out" "$repo/ai/secrets/registry.psd1")"
rm -rf "$repo/ai/secrets/registry.psd1" "$repo/ai/secrets/cs" "$src/tool" "$src/fork"

# --- machine.local.psd1 and file modes -------------------------------------------------------

# A search root under ~, as a Mac's machine.local.psd1 would write it.
mkdir -p "$home/src"
mv "$src/app" "$home/src/app"
printf "@{\n    SearchRoots = @('~/src')\n    Overlays = @(\n        '%s'\n    )\n}\n" "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"
rm "$home/src/app/.claude/skills/db-query/.secrets.env"
out="$(run)"; rc=$?
assert_eq "a search root under ~/ is the home directory's" "$secrets/db-query/.secrets.env" "$(readlink "$home/src/app/.claude/skills/db-query/.secrets.env")"

case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *)
        chmod 644 "$secrets/db-query/.secrets.env"
        chmod 755 "$secrets"
        run > /dev/null
        assert_eq "a decrypted file found readable by others is made its owner's alone" "rw-------" "$(ls -l "$secrets/db-query/.secrets.env" | cut -c2-10)"
        assert_eq "and so is ~/.agent-secrets" "rwx------" "$(ls -ld "$secrets" | cut -c2-10)"
        ;;
esac

printf "@{\n    Overlays = @('%s')\n}\n" "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"
out="$(run)"; rc=$?
assert_eq "no SearchRoots fails" "1" "$rc"
assert_eq "and says where to set them" "y" "$(says "$out" "SearchRoots")"

assert_summary "macos/deploy-secrets.sh"
