#!/bin/sh

# Installs, or with --uninstall removes, the LaunchAgent that runs macos/sync.sh at load (login,
# and now) and every 4 hours: the Mac's counterpart of powershell/install-sync-task.ps1
# (docs/adr/0009-a-launchagent-syncs-the-mac.md). The agent only pulls and re-links; it never
# commits or pushes. Safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/output.sh"

# Neutral, so the label names no owner.
LABEL="local.dotfiles.sync"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/dotfiles-sync.log"
EVERY_SECONDS=14400
DOMAIN="gui/$(id -u)"

# remove_old_agents: unload and remove an agent an older checkout installed under the label it used,
# <owner>.dotfiles-sync, so two agents never sync the same Mac.
remove_old_agents() {
    for old in "$HOME/Library/LaunchAgents/"*.dotfiles-sync.plist; do
        [ -f "$old" ] || continue
        old_label="${old##*/}"
        launchctl bootout "$DOMAIN/${old_label%.plist}" > /dev/null 2>&1
        rm -f "$old" && success "Removed the LaunchAgent ${old_label%.plist}, which this one replaces"
    done
}

case "${1:-}" in
    '') ;;
    --uninstall)
        remove_old_agents
        launchctl bootout "$DOMAIN/$LABEL" > /dev/null 2>&1
        rm -f "$PLIST"
        success "Removed the LaunchAgent $LABEL"
        exit 0 ;;
    *) die "Unknown option: $1 (usage: $0 [--uninstall])" ;;
esac

[ -f "$REPO/macos/sync.sh" ] || die "$REPO/macos/sync.sh not found"
remove_old_agents

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
