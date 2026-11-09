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
# In order: name the Mac, install Homebrew (with the Xcode command-line tools), gh, jq and node,
# sign gh in, clone or pull dotfiles and the overlay repo, write ai/secrets/machine.local.psd1, run
# macos/setup.sh and macos/install-sync-agent.sh, then each overlay's own macos/bootstrap.sh, and
# deploy the skill secrets when this Mac can decrypt them. It asks for the password once, on stdin
# (and hands it to Homebrew's sudo for the run, through SUDO_ASKPASS, so no cask installer asks), and gh
# signs in through the browser when it is not signed in; nothing else waits for a person. Safe to
# re-run: each step skips what is already done.
#
# DOTFILES_BRANCH and OVERLAY_BRANCH, when set, clone dotfiles and the overlay repo at those branches
# instead of their default ones, so a branch is tried on a new Mac before it merges (dotfiles-private's
# personal/machines/drill/mac-drill.sh --branch). A checkout already there is pulled as it stands.

set -u

DOTFILES_URL="${DOTFILES_URL:-https://github.com/hugoforte/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-}"
OVERLAY_BRANCH="${OVERLAY_BRANCH:-}"

# On a terminal, Homebrew 7 asks before installing anything, and its "[y/n]" would be one more
# thing waiting for a person; so would every brew run under this one, setup.sh's included.
HOMEBREW_NO_ASK=1; export HOMEBREW_NO_ASK

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

# sudo's cached credentials do not last: Homebrew runs `sudo --reset-timestamp` before its first sudo
# of each run (Library/Homebrew/utils/sudo.sh), so the first cask whose installer needs root asks
# again. Homebrew runs sudo -A, which asks a helper, when SUDO_ASKPASS is set. So ask here, once, and
# hand the password to a helper kept in a folder only this user can open, until this script ends.
# Not when sudo needs no password (sudo -v would still ask then, unless every sudoers rule says NOPASSWD).
keepalive="" askpass_dir=""
cleanup() {
    [ -z "$keepalive" ] || kill "$keepalive" 2> /dev/null
    [ -z "$askpass_dir" ] || rm -rf "$askpass_dir"
    [ ! -t 0 ] || stty echo 2> /dev/null
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

sudo -k
if ! sudo -n true 2> /dev/null; then
    askpass_dir="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-askpass.XXXXXX")" || die "could not create a folder for the sudo password helper"
    chmod 700 "$askpass_dir" || die "could not restrict $askpass_dir"
    attempts=0
    while :; do
        printf 'Password: ' >&2
        [ ! -t 0 ] || stty -echo 2> /dev/null
        IFS= read -r password; read_status=$?
        [ ! -t 0 ] || { stty echo 2> /dev/null; echo >&2; }
        [ "$read_status" = 0 ] || die "sudo is needed to install Homebrew and name the Mac: no password was given"
        if printf '%s\n' "$password" | sudo -S -p '' -v 2> /dev/null; then break; fi
        attempts=$((attempts + 1))
        [ "$attempts" -lt 3 ] || die "sudo is needed to install Homebrew and name the Mac: 3 passwords were refused"
        warn "Sorry, try again."
    done
    ( umask 077 && printf '%s' "$password" > "$askpass_dir/password" ) || die "could not write the sudo password helper"
    unset password
    printf '#!/bin/sh\nexec cat "%s/password"\n' "$askpass_dir" > "$askpass_dir/askpass" || die "could not write the sudo password helper"
    chmod 700 "$askpass_dir/askpass" || die "could not restrict the sudo password helper"
    SUDO_ASKPASS="$askpass_dir/askpass"; export SUDO_ASKPASS
fi

# Refresh the cached credentials until this script ends: Homebrew forgets them, and plain sudo
# elsewhere in the run uses them.
( while kill -0 $$ 2> /dev/null; do
      if [ -n "$askpass_dir" ]; then sudo -A -v; else sudo -n true; fi
      sleep 50
  done ) > /dev/null 2>&1 &
keepalive=$!

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

# --- Homebrew, gh, jq and node -----------------------------------------------------------------------

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

# dotfiles' own prerequisites, so no overlay's Brewfile has to carry them: gh clones, jq merges
# Claude Code's settings, and node runs the hooks those settings hold (ADR 0008).
for formula in gh jq node; do
    command -v "$formula" > /dev/null 2>&1 || brew install "$formula" || die "brew install $formula failed"
done
if gh auth status > /dev/null 2>&1; then
    ok "gh is signed in"
else
    say "Signing gh in to GitHub…"
    gh auth login --web --git-protocol https < /dev/tty || die "gh auth login failed"
fi

# --- Clones ------------------------------------------------------------------------------------------

# fetch <url> <folder> [branch]: clone the repo there, at the branch when one is given, or pull it
# when it is already there
fetch() {
    if [ -d "$2/.git" ]; then
        git -C "$2" pull --ff-only --quiet || die "git pull in $2 failed"
        ok "$2 is up to date"
    elif [ -e "$2" ]; then
        die "$2 exists and is not a git checkout"
    elif [ -n "${3:-}" ]; then
        # gh, so a private repo clones with its sign-in.
        gh repo clone "$1" "$2" -- --quiet --branch "$3" || die "could not clone $1 at $3 to $2"
        ok "Cloned $1 at $3 to $2"
    else
        gh repo clone "$1" "$2" -- --quiet || die "could not clone $1 to $2"
        ok "Cloned $1 to $2"
    fi
}

mkdir -p "$DIR" || die "could not create $DIR"
DIR="$(cd "$DIR" && pwd -P)"
DOTFILES="$DIR/dotfiles"
fetch "$DOTFILES_URL" "$DOTFILES" "$DOTFILES_BRANCH"

case "$OVERLAY_REPO" in
    *://*|git@*|/*) overlay_url="$OVERLAY_REPO" ;;
    *)              overlay_url="https://github.com/$OVERLAY_REPO.git" ;;
esac
overlay_name="$(basename "$OVERLAY_REPO" .git)"
OVERLAY_DIR="$DIR/$overlay_name"
fetch "$overlay_url" "$OVERLAY_DIR" "$OVERLAY_BRANCH"

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

# The overlays found in the clone, checked as a machine would read them before anything is written:
# none may clash with this repo or with another found here. Overlays a machine.local.psd1 already
# lists from elsewhere are setup.sh's to check, below.
. "$DOTFILES/ai/helpers/overlays.sh"
set --
while IFS= read -r o; do set -- "$@" "$o"; done <<EOF
$overlays
EOF
overlays_load "$DOTFILES" "$@" || exit 1
for path in $(printf '%s\n' "$OVERLAY_TABLE" | awk '$2 == "one" { print $1 }'); do
    overlay_sources "$path" > /dev/null || die "nothing was written; if dotfiles still carries what the overlay now holds, pull it"
done
merged_skill_registry > /dev/null || die "nothing was written"
. "$DOTFILES/ai/helpers/generated-file.sh"
. "$DOTFILES/ai/helpers/aws-config.sh"
aws_problem="$(aws_config_problem "$(generated_file_sources "$(overlay_sources aws/config)")")"
[ -z "$aws_problem" ] || die "$aws_problem; nothing was written"

local_psd1="$DOTFILES/ai/secrets/machine.local.psd1"
if [ -f "$local_psd1" ]; then
    listed="$(overlays_load "$DOTFILES" && printf '%s\n' "$OVERLAYS")" || exit 1
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
# The list is read from fd 3, so a script that reads stdin cannot swallow the scripts after it.
while IFS= read -r script <&3; do
    [ -n "$script" ] || continue
    say "Running ${script}…"
    sh "$script" || FAILED=1
done 3<<EOF || FAILED=1
$(overlay_sources macos/bootstrap.sh)
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
