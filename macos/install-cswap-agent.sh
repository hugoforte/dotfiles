#!/bin/sh

# Installs, or with --uninstall removes, the LaunchAgent that runs one `cswap auto --once` at load
# (login, and now) and every minute after, so claude-swap moves ~/.claude to another of the
# accounts it holds before the active one reaches its 5-hour or 7-day limit: the Mac's counterpart
# of powershell/install-cswap-task.ps1. Before any account is added (cswap add), each run logs that
# the login is not one it manages, so it can be installed first. Safe to re-run: with nothing
# changed it leaves the loaded agent alone.
#
#   sh install-cswap-agent.sh               install or update the agent, and load it
#   sh install-cswap-agent.sh --check       report only; exit 1 if it is missing or has drifted
#   sh install-cswap-agent.sh --uninstall   unload and remove it

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/output.sh"

# Neutral, so the label names no owner.
LABEL="local.dotfiles.cswap-auto"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/cswap-auto.log"
DOMAIN="gui/$(id -u)"

MODE=install
case "${1:-}" in
    '') ;;
    --check) MODE=check ;;
    --uninstall)
        launchctl bootout "$DOMAIN/$LABEL" > /dev/null 2>&1
        rm -f "$PLIST"
        success "Removed the LaunchAgent $LABEL"
        exit 0 ;;
    *) die "Unknown option: $1 (usage: $0 [--check | --uninstall])" ;;
esac

# By full path, so the agent does not depend on the PATH launchd starts it with, which lacks uv's
# ~/.local/bin. uv's own copy first: one found on PATH may be a project's virtualenv, gone later.
CSWAP="$HOME/.local/bin/cswap"
[ -x "$CSWAP" ] || CSWAP="$(command -v cswap 2> /dev/null)"
[ -n "$CSWAP" ] && [ -x "$CSWAP" ] || die "cswap is not in ~/.local/bin or on PATH; install claude-swap (uv tool install claude-swap, or uv \"claude-swap\" in a Brewfile)"

# xml <text>: text escaped for a plist string
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# A fresh process each minute picks up an upgraded claude-swap and keeps the log bounded: each run
# first moves a log over 1 MB (2048 blocks of 512 bytes) to cswap-auto.log.1. cswap keeps its usage
# readings and backoff on disk, so --once runs behave as one loop. --json writes one event a line.
# The shell gets cswap as $0 and the log as $1.
RUN='[ -z "$(find "$1" -size +2048 2> /dev/null)" ] || mv -f "$1" "$1.1"; exec "$0" auto --once --json >> "$1" 2>&1'

plist() {
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>$(xml "$RUN")</string>
        <string>$(xml "$CSWAP")</string>
        <string>$(xml "$LOG")</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>60</integer>
</dict>
</plist>
EOF
}

loaded() { launchctl print "$DOMAIN/$LABEL" > /dev/null 2>&1; }

if [ "$MODE" = "check" ]; then
    failed=0
    if [ "$(plist)" = "$(cat "$PLIST" 2> /dev/null)" ]; then
        success "The LaunchAgent $LABEL is installed, running $CSWAP"
    else
        warning "The LaunchAgent $LABEL is missing or differs; run sh macos/install-cswap-agent.sh"; failed=1
    fi
    if loaded; then
        success "The LaunchAgent $LABEL is loaded"
    else
        warning "The LaunchAgent $LABEL is not loaded; run sh macos/install-cswap-agent.sh"; failed=1
    fi
    exit "$failed"
fi

if [ "$(plist)" = "$(cat "$PLIST" 2> /dev/null)" ] && loaded; then
    success "The LaunchAgent $LABEL is installed and loaded"
    exit 0
fi

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")" || die "could not create $(dirname "$PLIST") or $(dirname "$LOG")"
plist > "$PLIST" || die "could not write $PLIST"

# bootout fails when the agent is not loaded, which on a first install it is not. It returns
# before launchd has let go of the job, and a bootstrap then fails (5: Input/output error), so
# wait for the job to be gone, for ten seconds at most.
launchctl bootout "$DOMAIN/$LABEL" > /dev/null 2>&1
waited=0
while loaded && [ "$waited" -lt 20 ]; do
    sleep 0.5
    waited=$((waited + 1))
done
launchctl bootstrap "$DOMAIN" "$PLIST" || die "launchctl could not load $PLIST"

success "Installed the LaunchAgent $LABEL"
info "    Runs $CSWAP auto --once at login, now and every minute. Log: $LOG. Accounts and usage: cswap list"
info "    Remove with: sh macos/install-cswap-agent.sh --uninstall"
