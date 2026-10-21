#!/bin/sh

# Fixture suite for macos/install-sync-agent.sh: the LaunchAgent plist it writes runs this
# checkout's macos/sync.sh at load and every 4 hours, it reloads the agent through launchctl,
# re-running it changes nothing, and --uninstall takes it out. launchctl is a stub that logs its
# arguments; where plutil exists (macOS), the plist must pass its lint.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

home="$work/home dir"
stubs="$work/stubs"
mkdir -p "$home" "$stubs"
# launchctl logs each call; `print` answers that the job is not loaded.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n[ "$1" != print ]\n' "$work/launchctl.log" > "$stubs/launchctl"
chmod +x "$stubs/launchctl"

HOME="$home"; export HOME
PATH="$stubs:$PATH"; export PATH

plist="$home/Library/LaunchAgents/local.dotfiles.sync.plist"
# An agent an older checkout installed, under a label that named its owner.
old="$home/Library/LaunchAgents/com.someone.dotfiles-sync.plist"
mkdir -p "$(dirname "$old")"
printf '<plist/>\n' > "$old"
agent()   { (cd "$work" && sh "$REPO_ROOT/macos/install-sync-agent.sh" "$@" 2>&1); }
has()     { if grep -qF -- "$1" "$plist"; then echo y; else echo n; fi; }
exists()  { if [ -e "$1" ]; then echo y; else echo n; fi; }
uid="$(id -u)"

out="$(agent)"; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "it writes the plist" "y" "$(exists "$plist")"
assert_eq "the agent is labelled local.dotfiles.sync, naming no one" "y" "$(has "<string>local.dotfiles.sync</string>")"
assert_eq "it unloads the agent an older checkout installed" "bootout gui/$uid/com.someone.dotfiles-sync" "$(head -n 1 "$work/launchctl.log")"
assert_eq "and removes its plist" "n" "$(exists "$old")"
assert_eq "it runs this checkout's macos/sync.sh" "y" "$(has "<string>$REPO_ROOT/macos/sync.sh</string>")"
assert_eq "quietly, since it logs to its own file" "y" "$(has "<string>--quiet</string>")"
assert_eq "at load" "y" "$(has "<key>RunAtLoad</key>")"
assert_eq "and every 4 hours" "y" "$(has "<integer>14400</integer>")"
assert_eq "anything sync.sh does not catch lands in its log" "y" "$(has "<string>$home/Library/Logs/dotfiles-sync.log</string>")"
assert_eq "it unloads any running agent of its own before loading" "bootout gui/$uid/local.dotfiles.sync" "$(grep -v 'com.someone' "$work/launchctl.log" | head -n 1)"
assert_eq "and loads this one last" "bootstrap gui/$uid $plist" "$(tail -n 1 "$work/launchctl.log")"
if command -v plutil > /dev/null 2>&1; then
    assert_eq "plutil accepts the plist" "0" "$(plutil -lint "$plist" > /dev/null 2>&1; echo $?)"
fi

first="$(cat "$plist")"
agent > /dev/null; rc=$?
assert_eq "re-running succeeds" "0" "$rc"
assert_eq "and writes the same plist" "$first" "$(cat "$plist")"

rm "$work/launchctl.log"
out="$(agent --uninstall)"; rc=$?
assert_eq "--uninstall succeeds" "0" "$rc"
assert_eq "--uninstall unloads the agent" "bootout gui/$uid/local.dotfiles.sync" "$(cat "$work/launchctl.log")"
assert_eq "--uninstall removes the plist" "n" "$(exists "$plist")"

assert_summary "macos/install-sync-agent.sh"
