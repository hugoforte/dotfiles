#!/bin/sh

# Decrypts managed skill secrets from ai/secrets/, here and in every overlay, and symlinks them
# into every matching checkout: powershell/deploy-secrets.ps1's contract, in sh for a Mac.
#
#   macos/deploy-secrets.sh           decrypt, discover, link; report each target
#   macos/deploy-secrets.sh --check   report only; exit 1 if anything would change
#
# Reads ai/secrets/machine.local.psd1 (SearchRoots, Overlays) and the ai/secrets/registry.psd1 of
# this repo and of every overlay. Each skill decrypts from the root that registered it, into
# ~/.agent-secrets/<skill>/, readable by its owner alone. An entry with no Marker belongs to a
# shipped skill, which reads its files from there and is never linked. Idempotent. A real file
# where a link goes is moved to ~/.agent-secrets/backups/, never left in the checkout. A failed
# decrypt leaves the previous decrypted copy in place. Any warning exits 1.
#
# The registries are read by awk, so an entry must put each key on a line of its own with a
# quoted value, Files as one @(...) on one line, as every registry here does, and a Remote beside
# every Marker. An entry it cannot read is an error. ai/helpers/overlays.sh reads them.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$REPO/ai/helpers/output.sh"
. "$REPO/ai/helpers/managed-link.sh"
. "$REPO/ai/helpers/overlays.sh"

MODE=deploy
case "${1:-}" in
    '')        ;;
    --check)   MODE=check ;;
    -h|--help) echo "Usage: $0 [--check]"; exit 0 ;;
    *)         die "Unknown option: $1 (usage: $0 [--check])" ;;
esac

# Plaintext is written below; nobody but its owner reads it.
umask 077

LOCAL_PSD1="$REPO/ai/secrets/machine.local.psd1"
SECRETS_HOME="$HOME/.agent-secrets"
# The field separator of a skill line; see merged_skill_registry.
FS="$REGISTRY_FS"

# What --check found out of place, counted where it means "this would change". A failed decrypt
# or an origin mismatch is a warning too, but not one a deploy would fix.
WARNED=0
DRIFT=0
warn() { warning "$1"; WARNED=$((WARNED + 1)); }

# --- Preconditions -------------------------------------------------------------------------------

command -v sops > /dev/null 2>&1 || die "sops not found. Install with: brew install sops"
[ -f "$LOCAL_PSD1" ] || die "$LOCAL_PSD1 not found. Copy machine.local.psd1.example to machine.local.psd1 and set SearchRoots."

overlays_load "$REPO" || exit 1
SKILLS="$(merged_skill_registry)" || exit 1

SEARCH_ROOTS=""
while IFS= read -r search_root; do
    [ -n "$search_root" ] && [ -d "$search_root" ] && SEARCH_ROOTS="${SEARCH_ROOTS:+$SEARCH_ROOTS
}$search_root"
done <<EOF
$(psd1_paths "$LOCAL_PSD1" SearchRoots)
EOF
[ -n "$SEARCH_ROOTS" ] || die "none of the SearchRoots in machine.local.psd1 exist; set SearchRoots to the folders your checkouts are in"

# --- Phase 1: decrypt to ~/.agent-secrets/<skill>/ -----------------------------------------------

info "Decrypting to $SECRETS_HOME"
while IFS="$FS" read -r id marker remote files registry; do
    [ -n "$id" ] || continue
    secrets_dir="${registry%/registry.psd1}/$id"
    for file in $files; do
        encrypted="$secrets_dir/$file"
        decrypted="$SECRETS_HOME/$id/$file"
        if [ ! -f "$encrypted" ]; then warn "$id/$file missing from $secrets_dir"; continue; fi

        mkdir -p "$SECRETS_HOME/$id"
        # umask covers what is made now; a folder made by hand earlier is closed here too.
        [ "$MODE" = "check" ] || chmod 700 "$SECRETS_HOME" "$SECRETS_HOME/$id"
        # A name of its own, so a sync and a deploy run by hand never write the same file.
        if ! tmp="$(mktemp "$decrypted.XXXXXX")"; then
            warn "$id/$file: could not make a temporary file in $SECRETS_HOME/$id"
            continue
        fi
        if ! sops decrypt --output "$tmp" "$encrypted" > /dev/null 2>&1 || [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            warn "$id/$file failed to decrypt (is this machine a recipient in .sops.yaml?)"
            continue
        fi
        if [ -f "$decrypted" ] && cmp -s "$tmp" "$decrypted"; then
            rm -f "$tmp"
            [ "$MODE" = "check" ] || chmod 600 "$decrypted"
            success "$id/$file current"
        elif [ "$MODE" = "check" ]; then
            rm -f "$tmp"
            DRIFT=$((DRIFT + 1))
            warn "$id/$file would be updated"
        else
            mv -f "$tmp" "$decrypted"
            success "$id/$file decrypted"
        fi
    done
done <<EOF
$SKILLS
EOF

# --- Phase 2 + 3: discover checkouts and link ----------------------------------------------------

echo ""
info "Checkouts under: $(printf '%s' "$SEARCH_ROOTS" | tr '\n' ',' | sed 's/,/, /g')"
while IFS= read -r search_root; do
    for dir in "$search_root"/*/; do
        dir="${dir%/}"
        [ -d "$dir" ] || continue
        name="${dir##*/}"
        while IFS="$FS" read -r id marker remote files registry; do
            [ -n "$marker" ] && [ -d "$dir/$marker" ] || continue

            # Without case, as deploy-secrets.ps1's -notmatch compares.
            origin="$(git -C "$dir" remote get-url origin 2>/dev/null)"
            origin_lower="$(printf '%s' "$origin" | tr '[:upper:]' '[:lower:]')"
            remote_lower="$(printf '%s' "$remote" | tr '[:upper:]' '[:lower:]')"
            case "$origin_lower" in
                '')                matches=false ;;
                *"$remote_lower"*) matches=true ;;
                *)                 matches=false ;;
            esac
            if [ "$matches" = "false" ]; then
                warn "$name: has $id but origin '$origin' does not match '$remote'; skipped"
                continue
            fi

            for file in $files; do
                plain="$SECRETS_HOME/$id/$file"
                target="$dir/$marker/$file"
                label="$name/$marker/$file"
                if [ ! -f "$plain" ]; then warn "$label: no decrypted source"; continue; fi

                if is_link_to "$plain" "$target"; then
                    success "$label"
                elif [ "$MODE" = "check" ]; then
                    DRIFT=$((DRIFT + 1))
                    if [ -e "$target" ] || [ -L "$target" ]; then
                        warn "$label: exists and is not the managed link"
                    else
                        warn "$label: missing"
                    fi
                elif link "$plain" "$target" "$SECRETS_HOME/backups/$name/$id"; then
                    success "$label: linked"
                else
                    warn "$label: could not be linked"
                fi
            done
        done <<EOF
$SKILLS
EOF
    done
done <<EOF
$SEARCH_ROOTS
EOF

# --- Summary -------------------------------------------------------------------------------------

echo ""
if [ "$WARNED" -eq 0 ]; then
    if [ "$MODE" = "check" ]; then success "Everything in place."; else success "Done."; fi
    exit 0
fi
[ "$DRIFT" -eq 0 ] || warning "$DRIFT item(s) would change. Run macos/deploy-secrets.sh to apply."
problems=$((WARNED - DRIFT))
[ "$problems" -eq 0 ] || warning "$problems warning(s) that deploying will not fix; see above."
exit 1
