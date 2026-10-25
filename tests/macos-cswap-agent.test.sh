#!/bin/sh

# Fixture suite for macos/install-cswap-agent.sh: the LaunchAgent plist it writes runs cswap auto at
# load and again a minute after it exits, it reloads the agent through launchctl, re-running it
# changes nothing, --uninstall takes it out, and with no cswap it refuses and writes nothing.
# launchctl and cswap are stubs; where plutil exists (macOS), the plist must pass its lint.

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
printf '#!/bin/sh\n' > "$stubs/cswap"
chmod +x "$stubs/launchctl" "$stubs/cswap"

HOME="$home"; export HOME
# Only the stubs and the system's own tools, so a real cswap on this machine is never found.
base_path="/usr/bin:/bin"
PATH="$stubs:$base_path"; export PATH

plist="$home/Library/LaunchAgents/local.dotfiles.cswap-auto.plist"
agent()   { (cd "$work" && sh "$REPO_ROOT/macos/install-cswap-agent.sh" "$@" 2>&1); }
has()     { if grep -qF -- "$1" "$plist"; then echo y; else echo n; fi; }
exists()  { if [ -e "$1" ]; then echo y; else echo n; fi; }
says()    { case "$out" in *"$1"*) echo y ;; *) echo n ;; esac; }
uid="$(id -u)"

out="$(agent)"; rc=$?
assert_eq "install succeeds" "0" "$rc"
assert_eq "it writes the plist" "y" "$(exists "$plist")"
assert_eq "the agent is labelled local.dotfiles.cswap-auto, naming no one" "y" "$(has "<string>local.dotfiles.cswap-auto</string>")"
assert_eq "it runs the cswap on PATH, by its full path" "y" "$(has "<string>$stubs/cswap</string>")"
assert_eq "as cswap auto" "y" "$(has "<string>auto</string>")"
assert_eq "writing one JSON event a line to its log" "y" "$(has "<string>--json</string>")"
assert_eq "at load" "y" "$(has "<key>RunAtLoad</key>")"
assert_eq "and again whenever it exits" "y" "$(has "<key>KeepAlive</key>")"
assert_eq "a minute later at the soonest" "y" "$(has "<integer>60</integer>")"
assert_eq "it logs to ~/Library/Logs/cswap-auto.log" "y" "$(has "<string>$home/Library/Logs/cswap-auto.log</string>")"
assert_eq "it unloads any running agent of its own before loading" "bootout gui/$uid/local.dotfiles.cswap-auto" "$(head -n 1 "$work/launchctl.log")"
assert_eq "and loads this one after" "bootstrap gui/$uid $plist" "$(tail -n 1 "$work/launchctl.log")"
if command -v plutil > /dev/null 2>&1; then
    assert_eq "plutil accepts the plist" "0" "$(plutil -lint "$plist" > /dev/null 2>&1; echo $?)"
fi

first="$(cat "$plist")"
agent > /dev/null; rc=$?
assert_eq "re-running succeeds" "0" "$rc"
assert_eq "and writes the same plist" "$first" "$(cat "$plist")"

# uv installs its tools in ~/.local/bin, which a shell that never sourced its profile lacks.
mkdir -p "$home/.local/bin"
mv "$stubs/cswap" "$home/.local/bin/cswap"
agent > /dev/null; rc=$?
assert_eq "with cswap off PATH, install still succeeds" "0" "$rc"
assert_eq "and runs the one uv installed in ~/.local/bin" "y" "$(has "<string>$home/.local/bin/cswap</string>")"

rm "$work/launchctl.log"
out="$(agent --uninstall)"; rc=$?
assert_eq "--uninstall succeeds" "0" "$rc"
assert_eq "--uninstall unloads the agent" "bootout gui/$uid/local.dotfiles.cswap-auto" "$(cat "$work/launchctl.log")"
assert_eq "--uninstall removes the plist" "n" "$(exists "$plist")"

rm "$home/.local/bin/cswap" "$work/launchctl.log"
out="$(agent)"; rc=$?
assert_eq "with no cswap anywhere, install fails" "1" "$rc"
assert_eq "and says how to install claude-swap" "y" "$(says "uv tool install claude-swap")"
assert_eq "and writes no plist" "n" "$(exists "$plist")"
assert_eq "and loads nothing" "n" "$(exists "$work/launchctl.log")"

assert_summary "macos/install-cswap-agent.sh"
