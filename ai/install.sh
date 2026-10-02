#!/bin/sh

# Installs the AI tooling in this repo into the agents' home directories by symlink.
# Components: CLAUDE.md, agents, skills, rig skills, overlay skills, Bruno collections, settings.
# See --help.

# Derive repo root from script location (works regardless of where repo is cloned)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
. "$ZSH/ai/helpers/output.sh"
. "$ZSH/ai/helpers/settings-reconcile.sh"

# On Git Bash (MSYS), `ln -s` silently copies unless native symlinks are enabled.
# Native symlinks need Windows Developer Mode or an elevated shell.
# NTFS ignores case in a path, and Git Bash keeps whatever capitals a path was typed with, so
# there two spellings of one checkout must compare equal.
FOLD_PATH_CASE=false
case "$(uname -s)" in
    MINGW*|MSYS*) export MSYS="winsymlinks:nativestrict"; FOLD_PATH_CASE=true ;;
esac

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SETTINGS_FRAGMENT="$ZSH/ai/claude/settings.json"

# Overlays ship Bruno collections too, under <overlay>/bruno/<collection>/, each linked into
# this one home so Bruno opens them all from one place. No collection lives in this public repo;
# the content is private, the mechanism is not.
BRUNO_DIR="$HOME/bruno"

# Skill directories: every ai/skills/<name>/ is linked into each of these.
# ~/.claude/skills is always used; the others only when their tool directory exists.
SKILL_TARGETS="$HOME/.claude/skills $HOME/.codex/skills $HOME/.copilot/skills"

TAB="$(printf '\t')"

skill_target_dirs() {
    for target in $SKILL_TARGETS; do
        parent="$(dirname "$target")"
        if [ "$target" = "$HOME/.claude/skills" ] || [ -d "$parent" ]; then
            echo "$target"
        fi
    done
}

# The rig checkout this machine has, if any. RIG_ROOT names one outright and is
# not fallen through: a RIG_ROOT that points nowhere is a misconfiguration to
# report, not a reason to go looking. Otherwise the same places powershell/rig.ps1
# looks, in the same order. Prints the root and returns 0, or returns 1.
rig_root() {
    if [ -n "$RIG_ROOT" ]; then
        root="$RIG_ROOT"
        case "$root" in
            [A-Za-z]:*) command -v cygpath > /dev/null 2>&1 && root="$(cygpath -u "$root")" ;;
        esac
        # A trailing separator would never match what readlink reports; see overlay_dirs.
        root="${root%/}"
        [ -f "$root/bin/rig.mjs" ] && { echo "$root"; return 0; }
        warning "RIG_ROOT=$RIG_ROOT has no bin/rig.mjs - no rig skills linked"
        return 1
    fi
    for root in /d/rig /c/rig "$HOME/rig"; do
        [ -f "$root/bin/rig.mjs" ] && { echo "$root"; return 0; }
    done
    return 1
}

# The overlay directories ai/secrets/machine.local.psd1 lists, one per line, in the order
# listed. Reads the `Overlays = @( ... )` entry up to its closing parenthesis and takes each
# single-quoted path from it. powershell/overlays.ps1 is the full reader; this is only enough
# to find the directories to audit.
overlay_dirs() {
    local_psd1="$ZSH/ai/secrets/machine.local.psd1"
    [ -f "$local_psd1" ] || return 0
    awk '/^[[:space:]]*#/ { next }
         /Overlays[[:space:]]*=/ { on = 1; sub(/.*Overlays[[:space:]]*=/, "") }
         on { print }
         on && /\)/ { exit }' "$local_psd1" |
        grep -o "'[^']*'" | tr -d "'" |
        while IFS= read -r dir; do
            case "$dir" in
                [A-Za-z]:*) command -v cygpath > /dev/null 2>&1 && dir="$(cygpath -u "$dir")" ;;
            esac
            # A trailing separator would make every link source path differ from what readlink
            # reports, so --check would see drift forever and the prune would never match.
            echo "${dir%/}"
        done
}

# ---------------------------------------------------------------------------
# Link primitives
# ---------------------------------------------------------------------------

# link <src> <dst>: point dst at src, backing up whatever real file was already there.
#
# A symlink at dst holds no content of its own, so it is replaced without a backup. A real file
# is someone's work: it is moved aside, never deleted, under the same <leaf>.backup.<timestamp>
# name powershell/managed-link.ps1 uses, so one convention shows up in both languages.
link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        backup="$dst.backup.$(date +%Y%m%d_%H%M%S)"
        if ! mv "$dst" "$backup"; then
            error "Could not move $dst aside to $backup - leaving it alone"
            return 1
        fi
        warning "$dst was not a symlink - backed it up to $backup"
    fi
    ln -s "$src" "$dst"
}

# same_path <a> <b>: true when both spell the same path (without case on Windows)
same_path() {
    if [ "$FOLD_PATH_CASE" = "true" ]; then
        [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ]
    else
        [ "$1" = "$2" ]
    fi
}

# is_link_to <src> <dst>: true when dst is a symlink to src
is_link_to() {
    [ -L "$2" ] && same_path "$(readlink "$2")" "$1"
}

# unlink_managed <src> <dst>: remove dst only if it is a symlink to src. A link someone pointed
# elsewhere at the same name is theirs: it is left in place, said, and the call returns 1.
unlink_managed() {
    [ -L "$2" ] || return 0
    if is_link_to "$1" "$2"; then
        rm -f "$2"
    else
        warning "$2 -> $(readlink "$2") (expected $1), left in place"
        return 1
    fi
}

# is_orphan_link <entry> <source_dir>: true when <entry> is a symlink into
# <source_dir> that no longer resolves. A skill or agent deleted from the repo
# leaves exactly this behind on every machine that had linked it, and a
# dangling link is not harmless: the agents still list the name and then fail
# to read it. Links pointing anywhere else are somebody else's business.
is_orphan_link() {
    [ -L "$1" ] || return 1
    [ -e "$1" ] && return 1
    case "$(readlink "$1")" in
        "$2"/*) return 0 ;;
    esac
    return 1
}

# prune_orphans <dir> <source_dir>: delete the orphans in <dir>
prune_orphans() {
    [ -d "$1" ] || return 0
    for entry in "$1"/*; do
        is_orphan_link "$entry" "$2" || continue
        rm -f "$entry"
        success "Removed stale link $entry"
    done
}

CHECK_FAILED=0

# check_link <src> <dst>: report the state of one managed link
check_link() {
    src="$1"; dst="$2"
    if [ -L "$dst" ]; then
        actual="$(readlink "$dst")"
        if [ "$actual" = "$src" ]; then
            success "$dst"
        else
            warning "$dst -> $actual (expected $src)"
            CHECK_FAILED=1
        fi
    elif [ -e "$dst" ]; then
        warning "$dst is a regular file or directory, not a symlink"
        CHECK_FAILED=1
    else
        warning "$dst missing"
        CHECK_FAILED=1
    fi
}

# check_orphans <dir> <source_dir>: report the orphans in <dir> as drift
check_orphans() {
    [ -d "$1" ] || return 0
    for entry in "$1"/*; do
        is_orphan_link "$entry" "$2" || continue
        warning "$entry is a stale link to something no longer in the repo"
        CHECK_FAILED=1
    done
}

# ---------------------------------------------------------------------------
# Components: each has install_<c>, uninstall_<c>, check_<c>
# ---------------------------------------------------------------------------

install_claude_md() {
    mkdir -p "$CLAUDE_DIR"
    link "$ZSH/ai/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" && success "Linked CLAUDE.md"
}
uninstall_claude_md() {
    unlink_managed "$ZSH/ai/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" && success "Removed CLAUDE.md link"
}
check_claude_md() {
    check_link "$ZSH/ai/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
}

install_agents() {
    mkdir -p "$CLAUDE_DIR/agents"
    for agent in "$ZSH"/ai/agents/*.md; do
        link "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
    prune_orphans "$CLAUDE_DIR/agents" "$ZSH/ai/agents"
    success "Linked agents into $CLAUDE_DIR/agents"
}
uninstall_agents() {
    for agent in "$ZSH"/ai/agents/*.md; do
        unlink_managed "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
    prune_orphans "$CLAUDE_DIR/agents" "$ZSH/ai/agents"
    success "Removed agent links"
}
check_agents() {
    for agent in "$ZSH"/ai/agents/*.md; do
        check_link "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
    done
    check_orphans "$CLAUDE_DIR/agents" "$ZSH/ai/agents"
}

install_skills() {
    for target in $(skill_target_dirs); do
        mkdir -p "$target"
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            link "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$ZSH/ai/skills"
        success "Linked skills into $target"
    done
}
uninstall_skills() {
    for target in $(skill_target_dirs); do
        [ -d "$target" ] || continue
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            unlink_managed "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$ZSH/ai/skills"
    done
    success "Removed skill links"
}
check_skills() {
    for target in $(skill_target_dirs); do
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            check_link "$skill" "$target/$(basename "$skill")"
        done
        check_orphans "$target" "$ZSH/ai/skills"
    done
}

# rig ships its own agent skills under <checkout>/skills/ and links none of them;
# this is the linker. Same targets and the same prune rules as the shipped skills,
# with rig's skills/ as the source dir, so each prune touches only its own links.
# A machine without rig has nothing to link and is not drifted.
install_rig_skills() {
    root="$(rig_root)" || { info "No rig checkout on this machine - no rig skills to link"; return 0; }
    [ -d "$root/skills" ] || { info "rig at $root ships no skills yet - run rig update"; return 0; }
    for target in $(skill_target_dirs); do
        mkdir -p "$target"
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            link "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$root/skills"
        success "Linked rig skills from $root into $target"
    done
}
uninstall_rig_skills() {
    root="$(rig_root)" || return 0
    for target in $(skill_target_dirs); do
        [ -d "$target" ] || continue
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            unlink_managed "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$root/skills"
    done
    success "Removed rig skill links"
}
check_rig_skills() {
    root="$(rig_root)" || { info "No rig checkout on this machine - no rig skills expected"; return 0; }
    [ -d "$root/skills" ] || return 0
    for target in $(skill_target_dirs); do
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            check_link "$skill" "$target/$(basename "$skill")"
        done
        check_orphans "$target" "$root/skills"
    done
}

# Overlays ship skills too, under <overlay>/ai/skills/*/: a skill whose text names something
# private cannot live in this public repo. Same targets and the same prune rules, with each
# overlay's ai/skills as a source dir. The link is named after the skill, so a name shipped
# from two places would have one silently replace the other; a name this repo, rig or an
# earlier overlay already ships is not linked. Install warns and carries on, so one clash cannot
# stop the sync that runs it; --check fails on it.

# overlay_skills: one line per overlay skill, in overlay order: its directory, a tab, and
# the directory already shipping that name, or nothing when the name is free. Names compare
# without case, as they do on the NTFS the links live on.
overlay_skills() {
    rig_skills=""
    root="$(rig_root)" && rig_skills="$root/skills"
    seen=""
    overlay_dirs | while IFS= read -r overlay; do
        for skill in "$overlay"/ai/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            name="$(basename "$skill")"
            key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
            clash=""
            if [ -d "$ZSH/ai/skills/$name" ]; then
                clash="$ZSH/ai/skills/$name"
            elif [ -n "$rig_skills" ] && [ -d "$rig_skills/$name" ]; then
                clash="$rig_skills/$name"
            else
                # "/" cannot appear in a skill name, so it ends the key unambiguously.
                case "$seen" in
                    *"$TAB$key/"*) clash="${seen#*"$TAB$key/"}"; clash="${clash%%"$TAB"*}" ;;
                esac
            fi
            [ -z "$clash" ] && seen="$seen$TAB$key/$skill$TAB"
            printf '%s\t%s\n' "$skill" "$clash"
        done
    done
}

# report_overlay_skill_clashes <overlay_skills output>: warn about each refused skill; false if any.
report_overlay_skill_clashes() {
    clashed=0
    while IFS="$TAB" read -r skill clash; do
        [ -n "$clash" ] || continue
        warning "$skill not linked: $clash already ships a skill with that name"
        clashed=1
    done <<EOF
$1
EOF
    [ "$clashed" = "0" ]
}

# each_overlay_orphans <dir> <prune_orphans|check_orphans> [subpath]: run it against every
# overlay. <subpath> is the directory within each overlay that sources the links, ai/skills by
# default; the Bruno component passes bruno.
each_overlay_orphans() {
    subpath="${3:-ai/skills}"
    overlays="$(overlay_dirs)"
    [ -n "$overlays" ] || return 0
    while IFS= read -r overlay; do
        "$2" "$1" "$overlay/$subpath"
    done <<EOF
$overlays
EOF
}

install_overlay_skills() {
    skills="$(overlay_skills)"
    report_overlay_skill_clashes "$skills" || :
    for target in $(skill_target_dirs); do
        mkdir -p "$target"
        while IFS="$TAB" read -r skill clash; do
            [ -n "$skill" ] && [ -z "$clash" ] || continue
            link "$skill" "$target/$(basename "$skill")"
        done <<EOF
$skills
EOF
        each_overlay_orphans "$target" prune_orphans
        if [ -n "$skills" ]; then success "Linked overlay skills into $target"; fi
    done
}
uninstall_overlay_skills() {
    skills="$(overlay_skills)"
    for target in $(skill_target_dirs); do
        [ -d "$target" ] || continue
        while IFS="$TAB" read -r skill clash; do
            [ -n "$skill" ] || continue
            # A refused name may still hold a link install made before the overlays were
            # reordered; it is ours only if it points here.
            [ -z "$clash" ] || is_link_to "$skill" "$target/$(basename "$skill")" || continue
            unlink_managed "$skill" "$target/$(basename "$skill")"
        done <<EOF
$skills
EOF
        each_overlay_orphans "$target" prune_orphans
    done
    success "Removed overlay skill links"
}
check_overlay_skills() {
    skills="$(overlay_skills)"
    report_overlay_skill_clashes "$skills" || CHECK_FAILED=1
    for target in $(skill_target_dirs); do
        while IFS="$TAB" read -r skill clash; do
            [ -n "$skill" ] && [ -z "$clash" ] || continue
            check_link "$skill" "$target/$(basename "$skill")"
        done <<EOF
$skills
EOF
        each_overlay_orphans "$target" check_orphans
    done
}

# Overlays ship Bruno collections under <overlay>/bruno/<collection>/, linked into ~/bruno so
# the Bruno app opens every overlay's collections from one home. The link is named after the
# collection, so a name shipped from two overlays would have one silently replace the other; the
# earlier overlay in the list keeps the name, the later is refused. Install warns and carries on,
# so one clash cannot stop the sync that runs it; --check fails on it. No collection lives in this
# public repo, so there is nothing of this repo's own to link beside them.

# overlay_bruno: one line per overlay Bruno collection, in overlay order: its directory, a tab,
# and the directory of an earlier overlay already shipping that name, or nothing when the name is
# free. Names compare without case, as they do on the NTFS the links live on.
overlay_bruno() {
    seen=""
    overlay_dirs | while IFS= read -r overlay; do
        for coll in "$overlay"/bruno/*/; do
            coll="${coll%/}"
            [ -d "$coll" ] || continue
            name="$(basename "$coll")"
            key="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
            clash=""
            # "/" cannot appear in a collection name, so it ends the key unambiguously.
            case "$seen" in
                *"$TAB$key/"*) clash="${seen#*"$TAB$key/"}"; clash="${clash%%"$TAB"*}" ;;
            esac
            [ -z "$clash" ] && seen="$seen$TAB$key/$coll$TAB"
            printf '%s\t%s\n' "$coll" "$clash"
        done
    done
}

# report_overlay_bruno_clashes <overlay_bruno output>: warn about each refused collection; false
# if any.
report_overlay_bruno_clashes() {
    clashed=0
    while IFS="$TAB" read -r coll clash; do
        [ -n "$clash" ] || continue
        warning "$coll not linked: $clash already ships a Bruno collection with that name"
        clashed=1
    done <<EOF
$1
EOF
    [ "$clashed" = "0" ]
}

install_bruno() {
    colls="$(overlay_bruno)"
    report_overlay_bruno_clashes "$colls" || :
    [ -n "$colls" ] && mkdir -p "$BRUNO_DIR"
    while IFS="$TAB" read -r coll clash; do
        [ -n "$coll" ] && [ -z "$clash" ] || continue
        link "$coll" "$BRUNO_DIR/$(basename "$coll")"
    done <<EOF
$colls
EOF
    each_overlay_orphans "$BRUNO_DIR" prune_orphans bruno
    [ -n "$colls" ] && success "Linked overlay Bruno collections into $BRUNO_DIR"
    return 0
}
uninstall_bruno() {
    colls="$(overlay_bruno)"
    [ -d "$BRUNO_DIR" ] || { success "Removed overlay Bruno collection links"; return 0; }
    while IFS="$TAB" read -r coll clash; do
        [ -n "$coll" ] || continue
        # A refused name may still hold a link install made before the overlays were reordered;
        # it is ours only if it points here.
        [ -z "$clash" ] || is_link_to "$coll" "$BRUNO_DIR/$(basename "$coll")" || continue
        unlink_managed "$coll" "$BRUNO_DIR/$(basename "$coll")"
    done <<EOF
$colls
EOF
    each_overlay_orphans "$BRUNO_DIR" prune_orphans bruno
    success "Removed overlay Bruno collection links"
}
check_bruno() {
    colls="$(overlay_bruno)"
    report_overlay_bruno_clashes "$colls" || CHECK_FAILED=1
    while IFS="$TAB" read -r coll clash; do
        [ -n "$coll" ] && [ -z "$clash" ] || continue
        check_link "$coll" "$BRUNO_DIR/$(basename "$coll")"
    done <<EOF
$colls
EOF
    each_overlay_orphans "$BRUNO_DIR" check_orphans bruno
}

# Settings are merged, not linked: ~/.claude/settings.json also holds machine-local state.
install_settings() {
    mkdir -p "$CLAUDE_DIR"
    if [ -f "$SETTINGS_FILE" ]; then
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    if reconcile_settings merge "$SETTINGS_FILE" "$SETTINGS_FRAGMENT"; then
        success "Merged ai/claude/settings.json into $SETTINGS_FILE"
    fi
}
uninstall_settings() {
    info "Settings are merged, not linked; nothing to remove from $SETTINGS_FILE"
}
check_settings() {
    reconcile_settings check "$SETTINGS_FILE" "$SETTINGS_FRAGMENT" || CHECK_FAILED=1
}

# Copy the managed keys from the live file back into the repo fragment.
export_settings() {
    reconcile_settings export "$SETTINGS_FILE" "$SETTINGS_FRAGMENT" || exit 1
    success "Wrote managed keys from $SETTINGS_FILE to ai/claude/settings.json (review with git diff)"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

MODE=install
INSTALL_CLAUDE_MD=true
INSTALL_AGENTS=true
INSTALL_SKILLS=true
INSTALL_RIG_SKILLS=true
INSTALL_OVERLAY_SKILLS=true
INSTALL_BRUNO=true
INSTALL_SETTINGS=true

disable_all() {
    INSTALL_CLAUDE_MD=false
    INSTALL_AGENTS=false
    INSTALL_SKILLS=false
    INSTALL_RIG_SKILLS=false
    INSTALL_OVERLAY_SKILLS=false
    INSTALL_BRUNO=false
    INSTALL_SETTINGS=false
}

show_help() {
    echo "Usage: $0 [MODE] [COMPONENT FLAGS]"
    echo ""
    echo "Symlinks CLAUDE.md, agents and skills from this repo into ~/.claude (and skills"
    echo "into ~/.codex and ~/.copilot when present), links the skills the rig checkout"
    echo "ships and the skills each overlay in ai/secrets/machine.local.psd1 ships the same way,"
    echo "links each overlay's Bruno collections (<overlay>/bruno/) into ~/bruno, and merges"
    echo "ai/claude/settings.json into ~/.claude/settings.json."
    echo ""
    echo "Modes:"
    echo "  (default)              Install"
    echo "  --check                Report link drift without changing anything (exit 1 on drift)"
    echo "  --uninstall            Remove the symlinks to what is listed now, and dangling ones into its"
    echo "                         sources; a link pointed elsewhere is left in place and named"
    echo "  --settings-export      Copy the managed settings keys from ~/.claude/settings.json back into the repo"
    echo ""
    echo "Component flags:"
    echo "  --claude-md-only       Only CLAUDE.md"
    echo "  --agents-only          Only agent files"
    echo "  --skills-only          Only skills"
    echo "  --rig-skills-only      Only the skills rig ships (RIG_ROOT, else D:/rig, C:/rig, ~/rig)"
    echo "  --overlay-skills-only  Only the skills overlays ship (<overlay>/ai/skills/)"
    echo "  --bruno-only           Only the Bruno collections overlays ship (<overlay>/bruno/)"
    echo "  --settings-only        Only settings merge"
    echo "  --no-claude-md         Skip CLAUDE.md"
    echo "  --no-agents            Skip agents"
    echo "  --no-skills            Skip skills"
    echo "  --no-rig-skills        Skip the skills rig ships"
    echo "  --no-overlay-skills    Skip the skills overlays ship"
    echo "  --no-bruno             Skip the Bruno collections overlays ship"
    echo "  --no-settings          Skip settings merge"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Needs: Windows Developer Mode or an elevated shell for symlinks; jq for settings."
}

while [ $# -gt 0 ]; do
    case $1 in
        --uninstall)           MODE=uninstall ;;
        --check)               MODE=check ;;
        --settings-export)     MODE=export; disable_all; INSTALL_SETTINGS=true ;;
        --claude-md-only)      disable_all; INSTALL_CLAUDE_MD=true ;;
        --agents-only)         disable_all; INSTALL_AGENTS=true ;;
        --skills-only)         disable_all; INSTALL_SKILLS=true ;;
        --rig-skills-only)     disable_all; INSTALL_RIG_SKILLS=true ;;
        --overlay-skills-only) disable_all; INSTALL_OVERLAY_SKILLS=true ;;
        --bruno-only)          disable_all; INSTALL_BRUNO=true ;;
        --settings-only)       disable_all; INSTALL_SETTINGS=true ;;
        --no-claude-md)        INSTALL_CLAUDE_MD=false ;;
        --no-agents)           INSTALL_AGENTS=false ;;
        --no-skills)           INSTALL_SKILLS=false ;;
        --no-rig-skills)       INSTALL_RIG_SKILLS=false ;;
        --no-overlay-skills)   INSTALL_OVERLAY_SKILLS=false ;;
        --no-bruno)            INSTALL_BRUNO=false ;;
        --no-settings)         INSTALL_SETTINGS=false ;;
        -h|--help)             show_help; exit 0 ;;
        *)                     echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

if [ "$MODE" = "install" ] && [ "$INSTALL_SETTINGS" = "true" ] && ! command -v jq > /dev/null 2>&1; then
    warning "jq not found - settings merge will be skipped (winget install jqlang.jq)"
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

case $MODE in
    install)   info "Installing AI tooling from $ZSH…" ;;
    uninstall) info "Removing AI tooling links…" ;;
    check)     info "Checking AI tooling links…" ;;
    export)    info "Exporting settings…" ;;
esac

[ "$INSTALL_CLAUDE_MD" = "true" ] && ${MODE}_claude_md
[ "$INSTALL_AGENTS" = "true" ]    && ${MODE}_agents
[ "$INSTALL_SKILLS" = "true" ]    && ${MODE}_skills
[ "$INSTALL_RIG_SKILLS" = "true" ] && ${MODE}_rig_skills
[ "$INSTALL_OVERLAY_SKILLS" = "true" ] && ${MODE}_overlay_skills
[ "$INSTALL_BRUNO" = "true" ]     && ${MODE}_bruno
[ "$INSTALL_SETTINGS" = "true" ]  && ${MODE}_settings

# Secrets under ai/secrets/, here and in every overlay, must never be committed in plaintext;
# verify on every check.
if [ "$MODE" = "check" ]; then
    if sh "$ZSH/ai/secrets/check-encrypted.sh"; then
        success "ai/secrets: all files encrypted"
    else
        CHECK_FAILED=1
    fi
    # A here-document rather than a pipe, so CHECK_FAILED is set in this shell, not a subshell.
    overlays="$(overlay_dirs)"
    [ -n "$overlays" ] && while IFS= read -r overlay; do
        if [ ! -d "$overlay" ]; then
            error "overlay $overlay listed in ai/secrets/machine.local.psd1 does not exist"
            CHECK_FAILED=1
        elif sh "$ZSH/ai/secrets/check-encrypted.sh" "$overlay/ai/secrets"; then
            success "$overlay/ai/secrets: all files encrypted"
        else
            CHECK_FAILED=1
        fi
    done <<EOF
$overlays
EOF
fi

echo ""
case $MODE in
    install)   success "Done" ;;
    uninstall) success "Done" ;;
    export)    success "Done" ;;
    check)
        if [ "$CHECK_FAILED" = "1" ]; then
            warning "Drift found - run $0 to fix"
            exit 1
        fi
        success "Everything in place"
        ;;
esac
