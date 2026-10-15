#!/bin/sh

# Installs, or with --uninstall removes, the LaunchAgent that runs macos/sync.sh at load (login,
# and now) and every 4 hours: the Mac's counterpart of powershell/install-sync-task.ps1
# (docs/adr/0009-a-launchagent-syncs-the-mac.md). The agent only pulls and re-links; it never
# commits or pushes. Safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/output.sh"

LABEL="com.hugoforte.dotfiles-sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/dotfiles-sync.log"
EVERY_SECONDS=14400
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

[ -f "$REPO/macos/sync.sh" ] || die "$REPO/macos/sync.sh not found"

# xml <text>: text escaped for a plist string
xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

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
        <string>/bin/sh</string>
        <string>$(xml "$REPO/macos/sync.sh")</string>
        <string>--quiet</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$EVERY_SECONDS</integer>
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
info "    Runs at login, now, and every $((EVERY_SECONDS / 3600)) hours. Log: $LOG"
info "    Remove with: sh macos/install-sync-agent.sh --uninstall"
