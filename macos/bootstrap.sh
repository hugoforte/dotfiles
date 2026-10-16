#!/bin/sh

# Sets up a new Mac from nothing: the Mac's counterpart of the Windows Quick start and
# powershell/install-overlays.ps1 together. Run it before anything is cloned:
#
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/hugoforte/dotfiles/main/macos/bootstrap.sh)" \
#       bootstrap --overlays <owner/repo> [--only <a,b>] [--name <KEY>] [--dir <folder>]
#
#   --overlays <owner/repo>  an overlay repo (or its URL), cloned beside dotfiles; every top-level
#                            directory is an overlay unless --only names some
#   --only <a,b>             just these overlays from it
#   --name <KEY>             the Mac's name; its machines/<KEY>.Brewfile is found by it
#   --dir <folder>           where dotfiles and the overlay repo go (default ~/source)
#
# In order: name the Mac, install Homebrew (with the Xcode command-line tools) and gh, sign gh in,
# clone or pull dotfiles and the overlay repo, write ai/secrets/machine.local.psd1, run
# macos/setup.sh and macos/install-sync-agent.sh, then each overlay's own macos/bootstrap.sh, and
# deploy the skill secrets when this Mac can decrypt them. It asks for the password once, and gh
# signs in through the browser when it is not signed in; nothing else waits for a person. Safe to
# re-run: each step skips what is already done.

set -u

DOTFILES_URL="${DOTFILES_URL:-https://github.com/hugoforte/dotfiles.git}"

say()  { printf '\033[0;34m%s\033[0m\n' "$1"; }
ok()   { printf '\033[0;32m[OK] %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m[!!] %s\033[0m\n' "$1"; }
die()  { printf '\033[0;31m[XX] %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
    echo "Usage: bootstrap.sh --overlays <owner/repo> [--only <a,b>] [--name <KEY>] [--dir <folder>]"
}

OVERLAY_REPO="" ONLY="" NAME="" DIR="$HOME/source"
while [ $# -gt 0 ]; do
    case "$1" in
        --overlays|--only|--name|--dir)
            [ $# -ge 2 ] || { usage; die "$1 needs a value"; }
            case "$1" in
                --overlays) OVERLAY_REPO="$2" ;;
                --only)     ONLY="$2" ;;
                --name)     NAME="$2" ;;
                --dir)      DIR="$2" ;;
            esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; die "Unknown option: $1" ;;
    esac
done
[ -n "$OVERLAY_REPO" ] || { usage; die "--overlays is required"; }
[ "$(uname -s)" = "Darwin" ] || die "bootstrap.sh is for macOS"

# --- The password, once ------------------------------------------------------------------------------

# Ask now, then keep sudo's memory of it fresh until this script ends, so no installer asks again.
# Not when sudo needs no password: -v still asks then, unless every sudoers rule says NOPASSWD.
sudo -n true 2> /dev/null || sudo -v || die "sudo is needed to install Homebrew and name the Mac"
( while kill -0 $$ 2> /dev/null; do sudo -n true; sleep 50; done ) > /dev/null 2>&1 &
keepalive=$!
trap 'kill "$keepalive" 2> /dev/null' EXIT

# --- Name ---------------------------------------------------------------------------------------------

if [ -n "$NAME" ]; then
    # HostName, which Bonjour never renames: the LocalHostName may be NAME-2 while another Mac has NAME.
    if [ "$(scutil --get HostName 2> /dev/null)" = "$NAME" ]; then
        ok "This Mac is named $NAME"
    else
        for key in ComputerName LocalHostName HostName; do
            sudo scutil --set "$key" "$NAME" || die "could not set $key to $NAME"
        done
        ok "Named this Mac $NAME"
    fi
fi

# --- Homebrew and gh ---------------------------------------------------------------------------------

for brew in "$(command -v brew 2> /dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -n "$brew" ] && [ -x "$brew" ] && break
    brew=""
done
if [ -z "$brew" ]; then
    say "Installing Homebrew, with the Xcode command-line tools…"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "the Homebrew installer failed"
    for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$brew" ] && break; done
fi
eval "$("$brew" shellenv)"
ok "Homebrew at $(brew --prefix)"

command -v gh > /dev/null 2>&1 || brew install gh || die "brew install gh failed"
if gh auth status > /dev/null 2>&1; then
    ok "gh is signed in"
else
    say "Signing gh in to GitHub…"
    gh auth login --web --git-protocol https < /dev/tty || die "gh auth login failed"
fi

# --- Clones ------------------------------------------------------------------------------------------

# fetch <url> <folder>: clone the repo there, or pull it when it is already there
fetch() {
    if [ -d "$2/.git" ]; then
        git -C "$2" pull --ff-only --quiet || die "git pull in $2 failed"
        ok "$2 is up to date"
    elif [ -e "$2" ]; then
        die "$2 exists and is not a git checkout"
    else
        # gh, so a private repo clones with its sign-in.
        gh repo clone "$1" "$2" -- --quiet || die "could not clone $1 to $2"
        ok "Cloned $1 to $2"
    fi
}

mkdir -p "$DIR" || die "could not create $DIR"
DIR="$(cd "$DIR" && pwd -P)"
DOTFILES="$DIR/dotfiles"
fetch "$DOTFILES_URL" "$DOTFILES"

case "$OVERLAY_REPO" in
    *://*|git@*|/*) overlay_url="$OVERLAY_REPO" ;;
    *)              overlay_url="https://github.com/$OVERLAY_REPO.git" ;;
esac
overlay_name="$(basename "$OVERLAY_REPO" .git)"
OVERLAY_DIR="$DIR/$overlay_name"
fetch "$overlay_url" "$OVERLAY_DIR"

# --- machine.local.psd1 ------------------------------------------------------------------------------

# Every top-level directory of the overlay repo is an overlay, unless --only names some.
overlays=""
for path in "$OVERLAY_DIR"/*/; do
    [ -d "$path" ] || continue
    name="$(basename "$path")"
    if [ -n "$ONLY" ]; then
        case ",$ONLY," in *",$name,"*) ;; *) continue ;; esac
    fi
    overlays="${overlays:+$overlays
}$OVERLAY_DIR/$name"
done
if [ -n "$ONLY" ]; then
    for name in $(printf '%s' "$ONLY" | tr ',' ' '); do
        [ -d "$OVERLAY_DIR/$name" ] || die "$OVERLAY_DIR has no overlay named $name"
    done
fi
[ -n "$overlays" ] || die "$OVERLAY_DIR has no overlay directories"

local_psd1="$DOTFILES/ai/secrets/machine.local.psd1"
if [ -f "$local_psd1" ]; then
    . "$DOTFILES/ai/helpers/overlays.sh"
    listed="$(psd1_paths "$local_psd1" Overlays)"
    missing="$(printf '%s\n' "$overlays" | while IFS= read -r o; do
        printf '%s\n' "$listed" | grep -Fqx "$o" || printf '%s\n' "$o"
    done)"
    [ -z "$missing" ] || die "$local_psd1 does not list $(printf '%s' "$missing" | tr '\n' ' ')- add it to Overlays, then run this again"
    ok "$local_psd1 lists the overlays"
else
    {
        printf '# Written by macos/bootstrap.sh. Per-machine settings; see machine.local.psd1.example.\n'
        printf '@{\n'
        printf "    SearchRoots = @('%s')\n" "$DIR"
        printf '    Overlays = @(\n'
        printf '%s\n' "$overlays" | while IFS= read -r o; do printf "        '%s'\n" "$o"; done
        printf '    )\n'
        printf '    OptionalTools = @()\n'
        printf '}\n'
    } > "$local_psd1" || die "could not write $local_psd1"
    ok "Wrote $local_psd1"
fi

# --- Setup, sync, overlays, secrets ------------------------------------------------------------------

FAILED=0
sh "$DOTFILES/macos/setup.sh" || FAILED=1
sh "$DOTFILES/macos/install-sync-agent.sh" || FAILED=1

# Each overlay's own steps: what is one person's or one employer's, so dotfiles cannot name it.
while IFS= read -r o; do
    [ -f "$o/macos/bootstrap.sh" ] || continue
    say "Running $o/macos/bootstrap.sh…"
    sh "$o/macos/bootstrap.sh" || FAILED=1
done <<EOF
$overlays
EOF

if sh "$DOTFILES/macos/deploy-secrets.sh" > /dev/null 2>&1; then
    ok "Skill secrets deployed"
else
    warn "Skill secrets not deployed: make this Mac a recipient (ai/secrets/README.md, \"Add a machine\"), then run macos/deploy-secrets.sh"
fi

echo ""
sh "$DOTFILES/macos/setup.sh" --check > /dev/null 2>&1 || { warn "dotfiles-check reports drift: run sh $DOTFILES/macos/setup.sh --check"; FAILED=1; }
if [ "$FAILED" = "1" ]; then
    die "Bootstrap finished with failures (above)"
fi
ok "Bootstrap complete; open a new terminal"
