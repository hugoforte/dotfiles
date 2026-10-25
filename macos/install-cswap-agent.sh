#!/bin/sh

# Installs, or with --uninstall removes, the LaunchAgent that runs `cswap auto` at load (login, and
# now), so claude-swap moves ~/.claude to another of the accounts it holds before the active one
# reaches its 5-hour or 7-day limit: the Mac's counterpart of powershell/install-cswap-task.ps1.
# Before any account is added (cswap add), cswap auto waits, logging that the login is not one it
# manages, so it can be installed first. Safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/output.sh"

# Neutral, so the label names no owner.
LABEL="local.dotfiles.cswap-auto"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/cswap-auto.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
    '') ;;
    --uninstall)
        launchctl bootout "$DOMAIN/$LABEL" > /dev/null 2>&1
        rm -f "$PLIST"
        success "Removed the LaunchAgent $LABEL"
        exit 0 ;;
    *) die "Unknown option: $1 (usage: $0 [--uninstall])" ;;
esac

# By full path, so the agent does not depend on the PATH launchd starts it with, which lacks uv's
# ~/.local/bin.
CSWAP="$(command -v cswap 2> /dev/null)"
[ -n "$CSWAP" ] || CSWAP="$HOME/.local/bin/cswap"
[ -x "$CSWAP" ] || die "cswap is not on PATH or at $CSWAP; install claude-swap (uv tool install claude-swap, or uv \"claude-swap\" in a Brewfile)"

# xml <text>: text escaped for a plist string
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# KeepAlive restarts cswap auto whenever it exits, and ThrottleInterval holds that to once a minute.
# --json writes one event a line, which is what goes to the log.
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(xml "$CSWAP")</string>
        <string>auto</string>
        <string>--json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>60</integer>
    <key>StandardOutPath</key>
    <string>$(xml "$LOG")</string>
    <key>StandardErrorPath</key>
    <string>$(xml "$LOG")</string>
</dict>
</plist>
EOF

# bootout fails when the agent is not loaded, which on a first install it is not. It returns
# before launchd has let go of the job, and a bootstrap then fails (5: Input/output error), so
# wait for the job to be gone, for ten seconds at most.
launchctl bootout "$DOMAIN/$LABEL" > /dev/null 2>&1
waited=0
while launchctl print "$DOMAIN/$LABEL" > /dev/null 2>&1 && [ "$waited" -lt 20 ]; do
    sleep 0.5
    waited=$((waited + 1))
done
launchctl bootstrap "$DOMAIN" "$PLIST" || die "launchctl could not load $PLIST"

success "Installed the LaunchAgent $LABEL"
info "    Runs $CSWAP auto at login and now. Log: $LOG. Accounts and usage: cswap list"
info "    Remove with: sh macos/install-cswap-agent.sh --uninstall"
