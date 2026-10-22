#!/bin/sh

# Pulls this repo and its overlay repos, then brings the Mac in line with them: macos/setup.sh
# (the links, ~/.gitconfig-overlays, the Brewfiles only when one changed, ai/install.sh), then
# the skill secrets when machine.local.psd1 declares SearchRoots. The Mac's counterpart of
# powershell/sync.ps1, run by the LaunchAgent macos/install-sync-agent.sh installs
# (docs/adr/0009-a-launchagent-syncs-the-mac.md). Safe unattended: fast-forward only, never
# commits or pushes.
#
#   macos/sync.sh           log to ~/Library/Logs/dotfiles-sync.log and the terminal
#   macos/sync.sh --quiet   log to the file alone, as the LaunchAgent runs it

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/overlays.sh"

QUIET=false
case "${1:-}" in
    '')      ;;
    --quiet) QUIET=true ;;
    *)       echo "Usage: $0 [--quiet]"; exit 1 ;;
esac

LOG="$HOME/Library/Logs/dotfiles-sync.log"
LOCAL_PSD1="$REPO/ai/secrets/machine.local.psd1"
mkdir -p "$(dirname "$LOG")"

log() {
    line="$(date '+%Y-%m-%d %H:%M:%S') $1"
    printf '%s\n' "$line" >> "$LOG"
    [ "$QUIET" = "true" ] || printf '%s\n' "$line"
}

# log_result <ok|failed> <output>: a child script's output, without the colour codes. Its warnings
# and errors when it succeeded; every line when it failed, since the reason may be a line of
# brew's or git's with no prefix, as sync.ps1 logs a failed install.sh. The escape is made by
# printf because BSD sed has no \x1b, and sed runs bytewise (LC_ALL=C) because BSD sed in a UTF-8
# locale refuses input it cannot decode.
ESC="$(printf '\033')"
log_result() {
    if [ "$1" = "ok" ]; then keep='^\[(!!|XX)\]'; else keep='.'; fi
    printf '%s\n' "$2" | LC_ALL=C sed "s/$ESC\[[0-9;]*m//g" | grep -E "$keep" |
        while IFS= read -r line; do log "  $line"; done
}

# A LaunchAgent starts with PATH=/usr/bin:/bin:/usr/sbin:/sbin, without Homebrew's jq and sops.
# A PATH that already finds brew, as a terminal's does, is left as it is.
command -v brew > /dev/null 2>&1 || for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$brew" ]; then
        eval "$("$brew" shellenv)"
        break
    fi
done

log "sync start ($REPO)"
failed=0

cd "$REPO" || exit 1
[ -z "$(git status --porcelain)" ] || log "working tree dirty; pulling anyway (ff-only) but local changes are yours to commit"
before="$(git rev-parse HEAD)"
if ! out="$(git pull --ff-only 2>&1)"; then
    log "git pull failed: $out"
    exit 1
fi
after="$(git rev-parse HEAD)"
if [ "$before" = "$after" ]; then
    log "already up to date at $(printf '%.7s' "$after")"
else
    log "updated $(printf '%.7s' "$before") -> $(printf '%.7s' "$after")"
fi

# A listed overlay that is gone stops the run: everything below would drop what it carries. Loaded
# in this shell, so OVERLAY_REPOS survives; a failure is loaded again in a subshell to log why.
if ! overlays_load "$REPO" 2> /dev/null; then
    log "$( (overlays_load "$REPO") 2>&1)"
    exit 1
fi

# Each overlay repo once, however many overlays it holds. A failed pull leaves that overlay as it
# was, which the steps below still apply; the run carries on and exits 1.
while IFS= read -r overlay_repo; do
    [ -n "$overlay_repo" ] || continue
    if out="$(git -C "$overlay_repo" pull --ff-only 2>&1)"; then
        log "pulled $overlay_repo"
    else
        log "git pull failed in $overlay_repo: $out"
        failed=1
    fi
done <<EOF
$OVERLAY_REPOS
EOF

if out="$(sh "$REPO/macos/setup.sh" --brew-if-changed 2>&1)"; then
    log "macos/setup.sh ok"
    log_result ok "$out"
else
    log "macos/setup.sh failed"
    log_result failed "$out"
    failed=1
fi

# Skill secrets only on a Mac whose machine.local.psd1 declares SearchRoots, as on Windows.
if [ -f "$LOCAL_PSD1" ] && grep -q '^[[:space:]]*SearchRoots[[:space:]]*=' "$LOCAL_PSD1"; then
    if out="$(sh "$REPO/macos/deploy-secrets.sh" 2>&1)"; then
        log "deploy-secrets.sh ok"
        log_result ok "$out"
    else
        log "deploy-secrets.sh failed"
        log_result failed "$out"
        failed=1
    fi
else
    log "deploy-secrets.sh skipped (no SearchRoots in ai/secrets/machine.local.psd1)"
fi

if [ "$failed" = "1" ]; then
    log "sync finished with failures (above)"
    exit 1
fi
log "sync done"
