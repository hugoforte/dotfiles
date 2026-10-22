#!/bin/sh

# Sets up a Mac from this repo, and reports whether one is set up. The macOS entry point beside
# powershell/setup.ps1 (docs/adr/0007-a-parallel-macos-entry-point.md).
#
#   macos/setup.sh                    link, write, brew bundle, then ai/install.sh; report each
#   macos/setup.sh --brew-if-changed  the same, with brew bundle only when a Brewfile changed
#                                     since the last bundle that succeeded (macos/sync.sh)
#   macos/setup.sh --check            report only; exit 1 if anything would change
#
# What it manages:
#   ~/.zshrc               -> macos/zshrc
#   ~/.gitconfig           -> macos/gitconfig
#   ~/.ssh/authorized_keys -> the one overlay's ssh/authorized_keys, if any
#   ~/.aws/config             written: every aws/config in this repo and the overlays, merged
#                             (ai/helpers/aws-config.sh)
#   ~/.gitconfig-overlays     written: an include of each overlay's git/gitconfig
#   Brewfiles                 each overlay's macos/Brewfile, then the one overlay's
#                             machines/<KEY>.Brewfile, KEY being the HostName (else the
#                             LocalHostName) uppercased
#                             (docs/adr/0008-a-brewfile-per-overlay.md); each path and checksum
#                             is kept in ~/Library/Application Support/dotfiles/brewfiles.cksum
#                             once every bundle succeeded, for --brew-if-changed
#   node                      checked for, since the agent-guard hook needs it; not installed
#   ai/install.sh             run, or run with --check
#
# Idempotent. A real file where a link goes is backed up first (docs/adr/0003).

# Physical, as macos/zshrc resolves it for dotfiles-check: a checkout reached through a symlink
# would otherwise be linked under one spelling and checked under another.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd -P)"

. "$REPO/ai/helpers/output.sh"
. "$REPO/ai/helpers/managed-link.sh"
. "$REPO/ai/helpers/overlays.sh"
. "$REPO/ai/helpers/aws-config.sh"

show_help() {
    echo "Usage: $0 [--check | --brew-if-changed]"
    echo ""
    echo "Links ~/.zshrc, ~/.gitconfig and ~/.ssh/authorized_keys, writes ~/.aws/config and ~/.gitconfig-overlays, applies"
    echo "each overlay's Brewfile and this Mac's, then runs ai/install.sh."
    echo ""
    echo "  --check            Report what would change without changing anything (exit 1 if anything would)"
    echo "  --brew-if-changed  Run brew bundle only when a Brewfile changed since it last succeeded"
    echo "  -h, --help         Show this help"
}

MODE=install
BREW_IF_CHANGED=false
case "${1:-}" in
    '')                ;;
    --check)           MODE=check ;;
    --brew-if-changed) BREW_IF_CHANGED=true ;;
    -h|--help)         show_help; exit 0 ;;
    *)                 echo "Unknown option: $1"; show_help; exit 1 ;;
esac
[ $# -le 1 ] || { echo "Unknown option: $2"; show_help; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macos/setup.sh is for macOS; on Windows run powershell/setup.ps1"

# What install could not do. --check counts drift in CHECK_FAILED, which managed-link.sh sets.
FAILED=0

overlays_load "$REPO" || exit 1

ssh_keys_source="$(overlay_sources ssh/authorized_keys)" || exit 1
machine_brewfile="$(overlay_sources "machines/{KEY}.Brewfile")" || exit 1

# --- Links ---------------------------------------------------------------------------------------

# managed <label> <src> <dst>: link dst to src, or with --check report it
managed() {
    if [ "$MODE" = "check" ]; then
        check_link "$2" "$3"
    elif is_link_to "$2" "$3"; then
        success "$1 already linked"
    else
        mkdir -p "$(dirname "$3")"
        if link "$2" "$3"; then success "$1 linked"; else FAILED=1; fi
    fi
}

case $MODE in
    install) info "Setting up this Mac from ${REPO}…" ;;
    check)   info "Checking this Mac against ${REPO}…" ;;
esac

managed "~/.zshrc" "$REPO/macos/zshrc" "$HOME/.zshrc"
managed "~/.gitconfig" "$REPO/macos/gitconfig" "$HOME/.gitconfig"
aws_sources="$(overlay_sources aws/config)"
if [ "$MODE" = "check" ]; then
    aws_config_check "$HOME/.aws/config" "$aws_sources"
else
    aws_config_apply "$HOME/.aws/config" "$aws_sources" || FAILED=1
fi
ssh_keys="$HOME/.ssh/authorized_keys"
if [ -n "$ssh_keys_source" ]; then
    managed "~/.ssh/authorized_keys" "$ssh_keys_source" "$ssh_keys"
elif [ -L "$ssh_keys" ] && case "$(readlink "$ssh_keys")" in */ssh/authorized_keys) true ;; *) false ;; esac; then
    # A link this made to an overlay no longer listed, or to a file since removed: the keys were
    # taken away, so they must stop working. A real file is someone's own, and is left alone.
    if [ "$MODE" = "check" ]; then
        warning "~/.ssh/authorized_keys links to keys no listed overlay ships ($(readlink "$ssh_keys"))"
        CHECK_FAILED=1
    elif rm -f "$ssh_keys"; then
        success "~/.ssh/authorized_keys removed: no listed overlay ships ssh/authorized_keys"
    else
        FAILED=1
    fi
else
    info "SSH keys: no overlay has ssh/authorized_keys; skipped"
fi

# --- ~/.gitconfig-overlays -----------------------------------------------------------------------

# The contents of ~/.gitconfig-overlays: one include per overlay that ships git/gitconfig, in
# overlay order, so a later overlay overrides an earlier one. macos/gitconfig includes it last.
gitconfig_overlays() {
    printf '# Generated by macos/setup.sh from the Overlays in ai/secrets/machine.local.psd1. Do not edit.\n'
    overlay_sources git/gitconfig | while IFS= read -r fragment; do
        printf '[include]\n\tpath = %s\n' "$fragment"
    done
}

include_file="$HOME/.gitconfig-overlays"
if [ -f "$include_file" ] && [ "$(cat "$include_file")" = "$(gitconfig_overlays)" ]; then
    success "~/.gitconfig-overlays"
elif [ "$MODE" = "check" ]; then
    warning "~/.gitconfig-overlays missing or out of date"
    CHECK_FAILED=1
else
    if gitconfig_overlays > "$include_file"; then
        success "~/.gitconfig-overlays written"
    else
        error "could not write $include_file"
        FAILED=1
    fi
fi

# --- Brewfiles -----------------------------------------------------------------------------------

# Before ai/install.sh, whose settings merge needs jq, should bootstrap not have installed it.
brewfiles="$(overlay_sources macos/Brewfile)"
[ -n "$machine_brewfile" ] && brewfiles="${brewfiles:+$brewfiles
}$machine_brewfile"

if [ -z "$OVERLAY_KEY" ]; then
    warning "this Mac has no HostName or LocalHostName, so no machines/<KEY>.Brewfile applies; name it with sudo scutil --set HostName <name>"
    CHECK_FAILED=1
fi

if [ -n "$brewfiles" ] && ! command -v brew > /dev/null 2>&1; then
    if [ "$MODE" = "check" ]; then
        warning "brew not found, so no Brewfile is applied; install Homebrew from https://brew.sh"
        CHECK_FAILED=1
    else
        error "brew not found; install Homebrew from https://brew.sh, then run this again"
        FAILED=1
    fi
    brewfiles=""
fi

# The Brewfiles as last applied with every bundle succeeding: each path and its checksum. A run
# that finds the same skips brew under --brew-if-changed.
brew_stamp_file="$HOME/Library/Application Support/dotfiles/brewfiles.cksum"
brew_stamp="$(while IFS= read -r brewfile; do
    [ -n "$brewfile" ] && printf '%s %s\n' "$brewfile" "$(cksum < "$brewfile")"
done <<EOF
$brewfiles
EOF
)"
if [ "$BREW_IF_CHANGED" = "true" ] && [ -f "$brew_stamp_file" ] && [ "$(cat "$brew_stamp_file")" = "$brew_stamp" ]; then
    success "Brewfiles unchanged since they were last applied"
    brewfiles=""
fi

bundle_failed=false
# --no-upgrade both ways: an entry is installed when missing and never upgraded, as a manifest's
# is on Windows, so an outdated formula is neither drift nor something a run replaces.
while IFS= read -r brewfile; do
    [ -n "$brewfile" ] || continue
    if [ "$MODE" = "check" ]; then
        if brew bundle check --no-upgrade --file="$brewfile" > /dev/null 2>&1; then
            success "$brewfile"
        else
            warning "$brewfile is not fully installed (brew bundle check --no-upgrade --verbose --file=$brewfile)"
            CHECK_FAILED=1
        fi
    elif brew bundle --no-upgrade --file="$brewfile"; then
        success "$brewfile applied"
    else
        error "brew bundle failed for $brewfile"
        bundle_failed=true
        FAILED=1
    fi
done <<EOF
$brewfiles
EOF

if [ "$MODE" = "install" ] && [ -n "$brewfiles" ] && [ "$bundle_failed" = "false" ]; then
    mkdir -p "$(dirname "$brew_stamp_file")"
    printf '%s\n' "$brew_stamp" > "$brew_stamp_file"
fi

# --- node ----------------------------------------------------------------------------------------

# After the Brewfiles, which may install it. The hooks ai/install.sh merges into Claude Code's
# settings run node, and agent-guard's blocks every Bash call when node cannot start.
if command -v node > /dev/null 2>&1; then
    success "node at $(command -v node)"
elif [ "$MODE" = "check" ]; then
    warning "node not found, so the agent-guard hook blocks every Bash call; brew install node"
    CHECK_FAILED=1
else
    error "node not found, so the agent-guard hook blocks every Bash call; brew install node, then run this again"
    FAILED=1
fi

# --- AI tooling ----------------------------------------------------------------------------------

if [ "$MODE" = "check" ]; then
    sh "$REPO/ai/install.sh" --check || CHECK_FAILED=1
else
    sh "$REPO/ai/install.sh" || FAILED=1
fi

echo ""
if [ "$MODE" = "check" ]; then
    if [ "$CHECK_FAILED" = "1" ]; then
        warning "Drift found - run macos/setup.sh to fix"
        exit 1
    fi
    success "This Mac is set up"
    exit 0
fi
if [ "$FAILED" = "1" ]; then
    error "Setup finished with failures (above)"
    exit 1
fi
success "Setup complete; open a new terminal to pick up ~/.zshrc"
