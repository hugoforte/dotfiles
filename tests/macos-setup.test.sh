#!/bin/sh

# Fixture suite for macos/setup.sh: the links it makes, the ~/.gitconfig-overlays it writes, the
# Brewfiles it applies, and --check reporting all of it without changing anything.
#
# It runs on any OS. uname, scutil and brew are stubs on PATH: uname says Darwin, scutil names the
# Mac, and brew logs each call to a file instead of installing anything. HOME has a space in it,
# and RIG_ROOT points at an empty directory so the real rig checkout stays out of it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

# Git Bash has no Unix modes for setup to set.
holds_modes=true
case "$(uname -s)" in
    MINGW*|MSYS*) MSYS="winsymlinks:nativestrict"; export MSYS; holds_modes=false ;;
esac

# Physical, as setup.sh links its checkout: the temp folder is often reached through a symlink
# (/var -> /private/var on macOS, /tmp a mount on Windows).
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
work="$(cd "$work" && pwd -P)"

repo="$work/repo"
home="$work/home dir"
stubs="$work/stubs"
personal="$work/private/personal"
second="$work/private/second"
brew_log="$work/brew.log"
mkdir -p "$repo/ai/helpers" "$repo/ai/claude" "$repo/ai/secrets" "$repo/ai/agents" "$repo/ai/skills/own" \
         "$repo/macos" "$home" "$stubs" \
         "$personal/git" "$personal/aws" "$personal/ssh" "$personal/macos" "$personal/machines" \
         "$second/git" "$second/macos"

cp "$REPO_ROOT"/macos/* "$repo/macos/"
cp "$REPO_ROOT/ai/install.sh" "$repo/ai/install.sh"
cp "$REPO_ROOT"/ai/helpers/*.sh "$repo/ai/helpers/"
printf 'exit 0\n' > "$repo/ai/secrets/check-encrypted.sh"
printf '# instructions\n' > "$repo/ai/CLAUDE.md"
printf -- '---\nname: helper\n---\n' > "$repo/ai/agents/helper.md"
printf -- '---\nname: own\n---\n' > "$repo/ai/skills/own/SKILL.md"
printf '{ "model": "sonnet" }\n' > "$repo/ai/claude/settings.json"

printf '[user]\n\temail = me@example.com\n' > "$personal/git/gitconfig"
printf '[core]\n\teditor = vim\n' > "$second/git/gitconfig"
printf '[profile dev]\n' > "$personal/aws/config"
printf 'ssh-ed25519 AAAA laptop\n' > "$personal/ssh/authorized_keys"
printf 'brew "jq"\n' > "$personal/macos/Brewfile"
printf 'brew "uv"\n' > "$second/macos/Brewfile"
printf 'cask "ghostty"\n' > "$personal/machines/MACBOOK.Brewfile"

# machine.local.psd1 holds Windows paths on a Windows machine, so on Git Bash write them that way.
win() { if command -v cygpath > /dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }
# overlays <dir>...: list these overlays in machine.local.psd1
overlays() {
    {
        printf '@{\n    Overlays = @(\n'
        for dir in "$@"; do printf "        '%s'\n" "$(win "$dir")"; done
        printf '    )\n}\n'
    } > "$repo/ai/secrets/machine.local.psd1"
}
overlays "$personal" "$second"

# The stubs. `brew bundle check` fails while $work/brew-missing exists, and `brew bundle` while
# $work/brew-fails does.
printf '#!/bin/sh\necho "${STUB_UNAME:-Darwin}"\n' > "$stubs/uname"
# scutil: LocalHostName is STUB_HOSTNAME, and HostName is STUB_HOST_NAME, unset (exit 1) by default.
printf '#!/bin/sh\ncase "$*" in\n  "--get LocalHostName") echo "${STUB_HOSTNAME-macbook}" ;;\n  "--get HostName") [ -n "${STUB_HOST_NAME:-}" ] && echo "$STUB_HOST_NAME" ;;\nesac\n' > "$stubs/scutil"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\ncase "$*" in "bundle check"*) [ ! -e "%s" ] ;; "bundle --no-upgrade"*) [ ! -e "%s" ] ;; esac\n' \
    "$brew_log" "$work/brew-missing" "$work/brew-fails" > "$stubs/brew"
chmod +x "$stubs/uname" "$stubs/scutil" "$stubs/brew"

HOME="$home"; export HOME
RIG_ROOT="$work/no-rig"; export RIG_ROOT
PATH="$stubs:$PATH"; export PATH
# A Mac has no COMPUTERNAME; on Windows it would name the machine over the scutil stub.
unset COMPUTERNAME

run()       { (cd "$work" && sh "$repo/macos/setup.sh" "$@" 2>&1); }
install()   { run > /dev/null; }
check()     { run --check; }
says()      { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }
exists()    { if [ -e "$1" ] || [ -L "$1" ]; then echo y; else echo n; fi; }

# --- install ---------------------------------------------------------------------------------

printf '# my old zshrc\n' > "$home/.zshrc"
install; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "~/.zshrc is linked to macos/zshrc" "$repo/macos/zshrc" "$(readlink "$home/.zshrc")"
set -- "$home"/.zshrc.backup.*
assert_eq "the real ~/.zshrc it displaced is backed up" "# my old zshrc" "$(cat "$1")"
assert_eq "~/.gitconfig is linked to macos/gitconfig" "$repo/macos/gitconfig" "$(readlink "$home/.gitconfig")"
assert_eq "~/.aws/config is a file, not a link" "n" "$([ -L "$home/.aws/config" ] && echo y || echo n)"
assert_eq "~/.aws/config holds the one overlay's aws/config under a line naming it" \
    "$(printf '# from %s\n[profile dev]' "$personal/aws/config")" "$(grep -v '^# Written by\|^# dotfiles-cksum\|^# Add a profile\|^$' "$home/.aws/config")"
assert_eq "~/.ssh/authorized_keys is linked to the one overlay that has it" "$personal/ssh/authorized_keys" "$(readlink "$home/.ssh/authorized_keys")"
assert_eq "~/.gitconfig-overlays includes each overlay's git/gitconfig, in order" \
    "$(printf '[include]\n\tpath = %s\n[include]\n\tpath = %s' "$personal/git/gitconfig" "$second/git/gitconfig")" \
    "$(grep -v '^#' "$home/.gitconfig-overlays")"
assert_eq "brew bundle applies each overlay's Brewfile, then the machine's, upgrading nothing" \
    "$(printf 'bundle --no-upgrade --file=%s\nbundle --no-upgrade --file=%s\nbundle --no-upgrade --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile" "$personal/machines/MACBOOK.Brewfile")" \
    "$(cat "$brew_log")"
assert_eq "ai/install.sh runs: ~/.claude/CLAUDE.md is linked" "$repo/ai/CLAUDE.md" "$(readlink "$home/.claude/CLAUDE.md")"

# --- check -----------------------------------------------------------------------------------

rm -f "$brew_log"
out="$(check)"; rc=$?
assert_eq "--check is clean once installed" "0" "$rc"
assert_eq "--check only asks brew, never installs, and an outdated entry is no drift" \
    "$(printf 'bundle check --no-upgrade --file=%s\nbundle check --no-upgrade --file=%s\nbundle check --no-upgrade --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile" "$personal/machines/MACBOOK.Brewfile")" \
    "$(cat "$brew_log")"

rm "$home/.zshrc"
out="$(check)"; rc=$?
assert_eq "--check fails on a missing link" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" ".zshrc missing")"
assert_eq "--check does not make it" "n" "$(exists "$home/.zshrc")"
install

printf '# edited\n' >> "$home/.gitconfig-overlays"
out="$(check)"; rc=$?
assert_eq "--check fails on a stale ~/.gitconfig-overlays" "1" "$rc"
assert_eq "--check leaves it as it was" "y" "$(says "$(cat "$home/.gitconfig-overlays")" "# edited")"
install
out="$(check)"; rc=$?
assert_eq "install rewrites ~/.gitconfig-overlays" "0" "$rc"

touch "$work/brew-missing"
out="$(check)"; rc=$?
assert_eq "--check fails when a Brewfile is not fully installed" "1" "$rc"
assert_eq "--check names the Brewfile" "y" "$(says "$out" "$second/macos/Brewfile")"
rm "$work/brew-missing"

rm "$home/.claude/CLAUDE.md"
out="$(check)"; rc=$?
assert_eq "--check fails on ai/install.sh's drift too" "1" "$rc"
install

# --- the machine's own Brewfile --------------------------------------------------------------

rm -f "$brew_log"
# In a subshell: macOS's /bin/sh keeps an assignment written before a function call after it.
(STUB_HOSTNAME=""; export STUB_HOSTNAME; install)
assert_eq "a Mac with no LocalHostName applies the overlays' Brewfiles alone" \
    "$(printf 'bundle --no-upgrade --file=%s\nbundle --no-upgrade --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile")" \
    "$(cat "$brew_log")"
out="$(STUB_HOSTNAME="" check)"; rc=$?
assert_eq "and --check fails, since the Mac is not named yet" "1" "$rc"
assert_eq "and says how to name it" "y" "$(says "$out" "LocalHostName")"

rm -f "$brew_log"
# Bonjour renames the LocalHostName when another Mac on the network has it: the old one, say.
(STUB_HOSTNAME="macbook-2"; STUB_HOST_NAME="macbook"; export STUB_HOSTNAME STUB_HOST_NAME; install)
assert_eq "the HostName names the machine Brewfile, over a LocalHostName Bonjour renamed" \
    "$(printf 'bundle --no-upgrade --file=%s\nbundle --no-upgrade --file=%s\nbundle --no-upgrade --file=%s' "$personal/macos/Brewfile" "$second/macos/Brewfile" "$personal/machines/MACBOOK.Brewfile")" \
    "$(cat "$brew_log")"

mkdir -p "$second/machines"
printf 'cask "zed"\n' > "$second/machines/MACBOOK.Brewfile"
out="$(run)"; rc=$?
assert_eq "a machine Brewfile in two overlays fails" "1" "$rc"
assert_eq "and names both" "y" "$(says "$out" "$second/machines/MACBOOK.Brewfile")"
rm -r "$second/machines"

# --- --brew-if-changed, as the sync runs it --------------------------------------------------

install
rm -f "$brew_log"
run --brew-if-changed > /dev/null; rc=$?
assert_eq "--brew-if-changed succeeds" "0" "$rc"
assert_eq "--brew-if-changed leaves brew alone when no Brewfile changed since install" "" "$(cat "$brew_log" 2>/dev/null)"

printf 'brew "ripgrep"\n' >> "$second/macos/Brewfile"
run --brew-if-changed > /dev/null
assert_eq "--brew-if-changed applies the Brewfiles once one changed" "3" "$(grep -c '^bundle --no-upgrade --file=' "$brew_log")"
rm -f "$brew_log"
run --brew-if-changed > /dev/null
assert_eq "and not again on the next run" "" "$(cat "$brew_log" 2>/dev/null)"

printf 'brew "fd"\n' >> "$personal/macos/Brewfile"
touch "$work/brew-fails"
out="$(run --brew-if-changed)"; rc=$?
assert_eq "a failed brew bundle fails the run" "1" "$rc"
rm -f "$work/brew-fails" "$brew_log"
run --brew-if-changed > /dev/null
assert_eq "and is tried again on the next" "3" "$(grep -c '^bundle --no-upgrade --file=' "$brew_log")"

# --- install failures ------------------------------------------------------------------------

touch "$work/brew-fails"
out="$(run)"; rc=$?
assert_eq "a failed brew bundle fails install" "1" "$rc"
assert_eq "and names the Brewfile" "y" "$(says "$out" "brew bundle failed for $personal/macos/Brewfile")"
rm "$work/brew-fails"

rm "$home/.gitconfig-overlays"
mkdir "$home/.gitconfig-overlays"
out="$(run)"; rc=$?
assert_eq "a ~/.gitconfig-overlays that cannot be written fails install" "1" "$rc"
rmdir "$home/.gitconfig-overlays"
install

# --- ~/.aws/config ---------------------------------------------------------------------------

aws="$home/.aws/config"
# sections: the section lines of ~/.aws/config, one per line, in order
sections() { grep '^\[' "$aws"; }

mkdir -p "$repo/aws" "$second/aws"
# The repo's: CRLF, and no final newline, with another source after it.
printf '[profile repo]\r\nregion = us-east-1' > "$repo/aws/config"
# The second overlay's: opening with a byte-order mark.
printf '\357\273\277[sso-session kealu]\nsso_region = us-east-1\n' > "$second/aws/config"
out="$(check)"; rc=$?
assert_eq "--check fails once another source has aws/config" "1" "$rc"
assert_eq "--check says the file is behind" "y" "$(says "$out" "behind the aws/config files it merges")"
install
assert_eq "every source merges, the repo first and then the overlays in order" \
    "$(printf '[profile repo]\n[profile dev]\n[sso-session kealu]')" "$(sections)"
assert_eq "the header counts the sources" "y" "$(says "$(head -n 1 "$aws")" "from 3 aws/config file(s)")"
assert_eq "a CRLF source is written with LF" "0" "$(tr -d -c '\r' < "$aws" | wc -c | tr -d ' ')"
assert_eq "a source with no final newline ends before the next one starts" "y" \
    "$(says "$(cat "$aws")" "$(printf 'region = us-east-1\n\n# from %s' "$personal/aws/config")")"
assert_eq "a source's byte-order mark is left out" "0" "$(grep -c "$(printf '\357\273\277')" "$aws")"
out="$(check)"; rc=$?
assert_eq "--check is clean once merged" "0" "$rc"

# clash <label> <second overlay's aws/config>: install fails and names the section, leaving the file
clash() {
    printf "$2" > "$second/aws/config"
    before="$(cat "$aws")"
    out="$(run)"; rc=$?
    assert_eq "$1 fails install" "1" "$rc"
    assert_eq "$1 leaves ~/.aws/config as it was" "$before" "$(cat "$aws")"
}
clash "a section two sources declare" '[profile dev]\n'
assert_eq "and names the section and both sources" "y" "$(says "$out" "[profile dev] is in both $personal/aws/config and $second/aws/config")"
out="$(check)"; rc=$?
assert_eq "--check fails on it too" "1" "$rc"
clash "a section line with a comment after it" '[profile dev] ; a copy\n'
clash "a quoted profile name" '[profile "dev"]\n'
printf '[default]\n' > "$repo/aws/config"
clash "[profile default] beside [default]" '[profile default]\n'
clash "a byte-order mark before a section another source declares" '\357\273\277[profile dev]\n'
printf '[profile repo]\n' > "$repo/aws/config"
printf '[profile Dev]\n' > "$second/aws/config"
out="$(run)"; rc=$?
assert_eq "names that differ only in case merge, as the AWS CLI reads them" "0" "$rc"
printf '[sso-session kealu]\nsso_region = us-east-1\n' > "$second/aws/config"
install

overlays "$personal" "$personal/" "$second"
install
assert_eq "an overlay listed twice goes in once" "1" "$(grep -c '^\[profile dev\]' "$aws")"
overlays "$personal" "$second"
install

printf '\n[profile added-by-aws-configure]\nregion = us-east-1\n' >> "$aws"
out="$(check)"; rc=$?
assert_eq "--check fails on a profile aws configure appended" "1" "$rc"
install
set -- "$home"/.aws/config.backup.*
assert_eq "install backs up a profile aws configure appended" "y" "$(says "$(cat "$1")" "[profile added-by-aws-configure]")"
assert_eq "and writes the merged file without it" "n" "$(says "$(cat "$aws")" "added-by-aws-configure")"
rm "$1"

if chmod 000 "$second/aws/config" 2> /dev/null && [ ! -r "$second/aws/config" ]; then
    before="$(cat "$aws")"
    out="$(run)"; rc=$?
    assert_eq "an unreadable source fails install" "1" "$rc"
    assert_eq "and names it" "y" "$(says "$out" "cannot read $second/aws/config")"
    assert_eq "and leaves ~/.aws/config as it was" "$before" "$(cat "$aws")"
fi
chmod 644 "$second/aws/config"
install

rm "$aws"
ln -s "$personal/aws/config" "$aws"
out="$(check)"; rc=$?
assert_eq "--check fails on the link setup used to make" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" "~/.aws/config is a link")"
install
assert_eq "install replaces the link with the merged file" "n" "$([ -L "$aws" ] && echo y || echo n)"
set -- "$home"/.aws/config.backup.*
assert_eq "without a backup" "n" "$(exists "$1")"
assert_eq "and leaves the link's source untouched" "[profile dev]" "$(cat "$personal/aws/config")"

printf '[profile added-by-aws-configure]\n' > "$aws"
out="$(check)"; rc=$?
assert_eq "--check fails on a file dotfiles did not write" "1" "$rc"
install
set -- "$home"/.aws/config.backup.*
assert_eq "install backs that file up" "[profile added-by-aws-configure]" "$(cat "$1")"
assert_eq "and writes the merged file" "y" "$(says "$(cat "$aws")" "# from $personal/aws/config")"
rm "$1"

rm -r "$repo/aws" "$second/aws"
mkdir -p "$work/unlisted/aws"
mv "$personal/aws/config" "$work/unlisted/aws/config"
out="$(check)"; rc=$?
assert_eq "--check fails on a merged file with no source left" "1" "$rc"
install
assert_eq "install removes it" "n" "$(exists "$aws")"
ln -s "$work/unlisted/aws/config" "$aws"
install
assert_eq "with no source, a link that still resolves stays, since someone made it" "y" "$(exists "$aws")"
rm "$aws"
ln -s "$work/gone/aws/config" "$aws"
install
assert_eq "and a link left dangling goes" "n" "$(exists "$aws")"
printf '[profile mine]\n' > "$aws"
out="$(run)"; rc=$?
assert_eq "with no source, a file of someone's own stays" "[profile mine]" "$(cat "$aws")"
assert_eq "and says it skipped" "y" "$(says "$out" "neither this repo nor an overlay has aws/config; skipped")"
rm "$aws"
mv "$work/unlisted/aws/config" "$personal/aws/config"
install

# --- ~/.ssh/config ---------------------------------------------------------------------------

ssh_config="$home/.ssh/config"
# mode <path>: its permissions as ls shows them
mode() { ls -ld "$1" | cut -c1-10; }

printf 'Host mine\n' > "$ssh_config"
out="$(run)"; rc=$?
assert_eq "with no ssh/config in an overlay, install succeeds" "0" "$rc"
assert_eq "and leaves an existing ~/.ssh/config untouched" "Host mine" "$(cat "$ssh_config")"
assert_eq "and says it skipped" "y" "$(says "$out" "neither this repo nor an overlay has ssh/config; skipped")"
out="$(check)"; rc=$?
assert_eq "--check counts no ssh/config as no drift" "0" "$rc"

mkdir -p "$second/ssh"
# The first ends inside a Host block, so the second's lines would apply to that host alone.
printf 'Host first\n    User one\n' > "$personal/ssh/config"
printf 'ServerAliveInterval 30\n' > "$second/ssh/config"
out="$(check)"; rc=$?
assert_eq "--check fails on a ~/.ssh/config dotfiles did not write" "1" "$rc"
assert_eq "--check leaves it as it was" "Host mine" "$(cat "$ssh_config")"
install
set -- "$home"/.ssh/config.backup.*
assert_eq "install backs up the ~/.ssh/config dotfiles did not write" "Host mine" "$(cat "$1")"
rm "$1"
assert_eq "every overlay's ssh/config merges in overlay order, each opening with Match all" \
    "$(printf '# from %s\nMatch all\nHost first\n    User one\n# from %s\nMatch all\nServerAliveInterval 30' "$personal/ssh/config" "$second/ssh/config")" \
    "$(grep -v '^# Written by\|^# dotfiles-cksum\|^# Add a host\|^$' "$ssh_config")"
if [ "$holds_modes" = "true" ]; then
    assert_eq "~/.ssh/config is mode 600" "-rw-------" "$(mode "$ssh_config")"
    assert_eq "~/.ssh is mode 700" "drwx------" "$(mode "$home/.ssh")"
fi
if command -v ssh > /dev/null 2>&1; then
    assert_eq "a later overlay's setting applies to every host, though an earlier one ended in a Host block" \
        "serveraliveinterval 30" "$(ssh -G -F "$ssh_config" elsewhere 2> /dev/null | grep '^serveraliveinterval ')"
fi
out="$(check)"; rc=$?
assert_eq "--check is clean once merged" "0" "$rc"

rm "$ssh_config"
out="$(check)"; rc=$?
assert_eq "--check fails on a missing ~/.ssh/config" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" "~/.ssh/config missing")"
assert_eq "--check does not write it" "n" "$(exists "$ssh_config")"
install

printf 'Compression yes\n' >> "$second/ssh/config"
before="$(cat "$ssh_config")"
out="$(check)"; rc=$?
assert_eq "--check fails on a ~/.ssh/config behind its sources" "1" "$rc"
assert_eq "--check says so" "y" "$(says "$out" "~/.ssh/config is behind the ssh/config files it merges")"
assert_eq "--check leaves it as it was" "$before" "$(cat "$ssh_config")"
install
assert_eq "install rewrites it" "y" "$(says "$(cat "$ssh_config")" "Compression yes")"

if [ "$holds_modes" = "true" ]; then
    chmod 644 "$ssh_config"
    chmod 755 "$home/.ssh"
    install
    assert_eq "install sets ~/.ssh/config back to 600" "-rw-------" "$(mode "$ssh_config")"
    assert_eq "and ~/.ssh back to 700" "drwx------" "$(mode "$home/.ssh")"
fi

rm -r "$personal/ssh/config" "$second/ssh"
out="$(check)"; rc=$?
assert_eq "--check fails on a merged ~/.ssh/config with no source left" "1" "$rc"
install
assert_eq "install removes the file it wrote" "n" "$(exists "$ssh_config")"
install

# --- reading machine.local.psd1 --------------------------------------------------------------

mv "$repo/ai/secrets/machine.local.psd1" "$work/machine.local.psd1.saved"
out="$(run)"; rc=$?
assert_eq "a Mac with no machine.local.psd1 yet sets up without overlays" "0" "$rc"
assert_eq "and, with no aws/config left, removes the merged file" "n" "$(exists "$home/.aws/config")"
mv "$work/machine.local.psd1.saved" "$repo/ai/secrets/machine.local.psd1"

printf '@{\n    Overlays = @(\n        "%s"\n    )\n}\n' "$(win "$personal")" > "$repo/ai/secrets/machine.local.psd1"
install
assert_eq "a double-quoted overlay path is read too" "y" "$(says "$(cat "$home/.aws/config")" "# from $personal/aws/config")"
overlays "$personal" "$second"
install

# --- a checkout reached through a symlink ----------------------------------------------------

# zshrc finds the checkout by resolving the ~/.zshrc link to its physical path, so dotfiles-check
# runs setup.sh from there; a setup run through the symlink must leave links that check accepts.
ln -s "$repo" "$work/via-link"
(cd "$work" && sh "$work/via-link/macos/setup.sh" > /dev/null 2>&1)
assert_eq "setup run through a symlinked checkout links the physical path" "$(cd "$repo" && pwd -P)/macos/zshrc" "$(readlink "$home/.zshrc")"
out="$(check)"; rc=$?
assert_eq "and --check from the physical path is clean" "0" "$rc"
rm "$work/via-link"

# --- node ------------------------------------------------------------------------------------

# PATH without every directory that holds a node, so node cannot be found.
no_node_path="$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r dir; do
    [ -n "$dir" ] && [ ! -x "$dir/node" ] && [ ! -x "$dir/node.exe" ] && printf '%s:' "$dir"
done)"

out="$(PATH="$no_node_path" run)"; rc=$?
assert_eq "install without node fails" "1" "$rc"
assert_eq "and says how to install it" "y" "$(says "$out" "node not found, so the agent-guard hook blocks every Bash call; brew install node")"
out="$(PATH="$no_node_path" check)"; rc=$?
assert_eq "--check without node fails" "1" "$rc"
assert_eq "and names it" "y" "$(says "$out" "node not found")"
install

# --- refusals --------------------------------------------------------------------------------

out="$(run --check extra)"; rc=$?
assert_eq "an argument it does not take is refused" "1" "$rc"

mkdir -p "$second/ssh"
printf 'ssh-ed25519 BBBB desktop\n' > "$second/ssh/authorized_keys"
out="$(run)"; rc=$?
assert_eq "ssh/authorized_keys from two overlays fails" "1" "$rc"
assert_eq "and names both" "y" "$(says "$out" "$second/ssh/authorized_keys")"
rm -r "$second/ssh"

mv "$personal/ssh/authorized_keys" "$work/authorized_keys.saved"
rm "$home/.ssh/authorized_keys"
out="$(run)"; rc=$?
assert_eq "no overlay with ssh/authorized_keys still sets up" "0" "$rc"
assert_eq "and says it skipped the keys" "y" "$(says "$out" "no overlay has ssh/authorized_keys; skipped")"
assert_eq "and leaves ~/.ssh/authorized_keys absent" "n" "$(exists "$home/.ssh/authorized_keys")"
mv "$work/authorized_keys.saved" "$personal/ssh/authorized_keys"
install

# Keys taken out of every listed overlay must stop working, though the old checkout is still there.
overlays "$second"
out="$(check)"; rc=$?
assert_eq "--check fails on a keys link no listed overlay ships" "1" "$rc"
assert_eq "--check names it" "y" "$(says "$out" "~/.ssh/authorized_keys links to keys no listed overlay ships")"
assert_eq "--check leaves it" "y" "$(exists "$home/.ssh/authorized_keys")"
install
assert_eq "install removes a keys link no listed overlay ships" "n" "$(exists "$home/.ssh/authorized_keys")"
printf 'ssh-rsa CCCC mine\n' > "$home/.ssh/authorized_keys"
install
assert_eq "and leaves a real ~/.ssh/authorized_keys alone" "ssh-rsa CCCC mine" "$(cat "$home/.ssh/authorized_keys")"
rm "$home/.ssh/authorized_keys"
overlays "$personal" "$second"
install

overlays "$personal" "$work/private/gone"
out="$(run)"; rc=$?
assert_eq "a listed overlay that does not exist fails" "1" "$rc"
assert_eq "and names it" "y" "$(says "$out" "gone")"
overlays "$personal" "$second"

out="$(STUB_UNAME=Linux run)"; rc=$?
assert_eq "anywhere but macOS it refuses" "1" "$rc"
assert_eq "and points at the Windows setup" "y" "$(says "$out" "powershell/setup.ps1")"

assert_summary "macos/setup.sh"
