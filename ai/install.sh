#!/bin/sh

# Installs the AI tooling in this repo into the agents' home directories by symlink.
# Components: CLAUDE.md, agents (this repo's and the overlays'), rules, skills, rig skills, overlay
# skills, Bruno collections, settings.
# The Claude ones apply to ~/.claude and to every extra Claude config folder (see CLAUDE_DIRS).
# See --help.

# Derive repo root from script location (works regardless of where repo is cloned)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ZSH="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source helper functions
. "$ZSH/ai/helpers/output.sh"
. "$ZSH/ai/helpers/settings-reconcile.sh"
. "$ZSH/ai/helpers/managed-link.sh"
. "$ZSH/ai/helpers/overlays.sh"

CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
SETTINGS_FRAGMENT="$ZSH/ai/claude/settings.json"

# Where the settings' hooks find their scripts (see settings-reconcile.sh). An app started from
# the Dock has launchd's PATH, which lacks bin/, so a hook named bare would not be found. On
# Windows the C:/ form, which node there reads.
HOOK_BIN="$ZSH/bin"
if command -v cygpath > /dev/null 2>&1; then
    HOOK_BIN="$(cygpath -m "$HOOK_BIN")"
fi

# Overlays ship Bruno collections too, under <overlay>/bruno/<collection>/, each linked into
# this one home so Bruno opens them all from one place. No collection lives in this public repo;
# the content is private, the mechanism is not.
BRUNO_DIR="$HOME/bruno"

TAB="$(printf '\t')"

# The Claude config folders, one per line: ~/.claude, then each extra folder the overlays name in
# their ai/claude/config-dirs, or in this machine's machines/<KEY>.config-dirs. Each gets exactly what ~/.claude gets: CLAUDE.md, agents, skills and
# the managed settings. Nothing else in a folder is touched, so its login (.credentials.json),
# .claude.json, history and projects stay Claude Code's. Set by resolve_claude_dirs; a path may
# hold spaces, so loop over it line by line, never with `for`.
CLAUDE_DIRS="$CLAUDE_DIR"

# config_dir_path <line>: print the folder one config-dirs line names. A line is one path,
# surrounding whitespace ignored: absolute (/..., C:\... or C:/...) or under the home directory
# (~/... or ~\...). A # at the start of a line, or after whitespace, starts a comment that
# runs to the end of the line. Returns 1 for a line naming no folder (blank or all comment), and
# 2, printing the path, for one that is not absolute, is the root or the home folder itself, or
# is a drive path with no cygpath to convert it.
config_dir_path() {
    path="${1#"${1%%[![:space:]]*}"}"
    path="${path%%[[:space:]]"#"*}"
    path="${path%"${path##*[![:space:]]}"}"
    case "$path" in
        ''|'#'*) return 1 ;;
        '~') path="$HOME" ;;
        '~/'*|'~\'*) path="$HOME/$(printf '%s' "${path#??}" | tr '\\' '/')" ;;
    esac
    case "$path" in
        /*) ;;
        [A-Za-z]:[\\/]*)
            command -v cygpath > /dev/null 2>&1 || { printf '%s\n' "$path"; return 2; }
            path="$(cygpath -u "$path")" ;;
        *) printf '%s\n' "$path"; return 2 ;;
    esac
    # Lexically: repeated slashes collapse, . segments go, and a trailing slash goes, so ~/. and //
    # cannot pass for something other than home or root. A .. segment is refused outright.
    path="$(printf '%s\n' "$path" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#/\./#/#g' -e 's#/\.$##' -e 's#/$##')"
    # The root or the home folder itself is never a Claude config folder.
    case "$path" in ''|"${HOME%/}"|*/..|*/../*) printf '%s\n' "${1}"; return 2 ;; esac
    printf '%s\n' "$path"
}

# resolve_claude_dirs: add each folder the overlays name to CLAUDE_DIRS, once: a folder already
# there, ~/.claude included, is not added again. An overlay names them in ai/claude/config-dirs for
# every machine, and in machines/<KEY>.config-dirs for the one machine whose OVERLAY_KEY is KEY, in
# the same format. A path that is not absolute is warned about, never created, and is drift to
# --check.
resolve_claude_dirs() {
    while IFS= read -r file; do
        [ -z "$file" ] || add_config_dirs "$file"
    done <<EOF
$(overlay_sources ai/claude/config-dirs; overlay_sources "machines/{KEY}.config-dirs")
EOF
}

# add_config_dirs <file>: add each folder one config-dirs file names to CLAUDE_DIRS. No file adds
# nothing.
add_config_dirs() {
    [ -f "$1" ] || return 0
    # Through a here-document: the last line counts without a newline after it.
    lines="$(tr -d '\r' < "$1")"
    while IFS= read -r line; do
        dir="$(config_dir_path "$line")"
        case $? in
            1) continue ;;
            2) warning "$1: $dir is not an absolute path or ~/..., or is / or ~ itself - skipped"
               CHECK_FAILED=1
               continue ;;
        esac
        known=false
        while IFS= read -r claude_dir; do
            same_path "$claude_dir" "$dir" && known=true
        done <<EOF
$CLAUDE_DIRS
EOF
        [ "$known" = "true" ] || CLAUDE_DIRS="$CLAUDE_DIRS
$dir"
    done <<EOF
$lines
EOF
}

# Skill directories: every ai/skills/<name>/ is linked into each of these.
# Each Claude config folder's skills/ is always used; Codex's and Copilot's only when their tool
# directory exists.
skill_target_dirs() {
    while IFS= read -r dir; do
        echo "$dir/skills"
    done <<EOF
$CLAUDE_DIRS
EOF
    for target in "$HOME/.codex/skills" "$HOME/.copilot/skills"; do
        if [ -d "$(dirname "$target")" ]; then
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
        # A trailing separator would never match what readlink reports; see _overlay_path.
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

# ---------------------------------------------------------------------------
# Components: each has install_<c>, uninstall_<c>, check_<c>
# ---------------------------------------------------------------------------

install_claude_md() {
    while IFS= read -r dir; do
        mkdir -p "$dir"
        link "$ZSH/ai/CLAUDE.md" "$dir/CLAUDE.md" && success "Linked CLAUDE.md into $dir"
    done <<EOF
$CLAUDE_DIRS
EOF
}
uninstall_claude_md() {
    while IFS= read -r dir; do
        unlink_managed "$ZSH/ai/CLAUDE.md" "$dir/CLAUDE.md" && success "Removed CLAUDE.md link from $dir"
    done <<EOF
$CLAUDE_DIRS
EOF
}
check_claude_md() {
    while IFS= read -r dir; do
        check_link "$ZSH/ai/CLAUDE.md" "$dir/CLAUDE.md"
    done <<EOF
$CLAUDE_DIRS
EOF
}

install_agents() {
    while IFS= read -r dir; do
        mkdir -p "$dir/agents"
        for agent in "$ZSH"/ai/agents/*.md; do
            link "$agent" "$dir/agents/$(basename "$agent")"
        done
        prune_orphans "$dir/agents" "$ZSH/ai/agents"
        success "Linked agents into $dir/agents"
    done <<EOF
$CLAUDE_DIRS
EOF
    overlay_agents install
}
uninstall_agents() {
    while IFS= read -r dir; do
        for agent in "$ZSH"/ai/agents/*.md; do
            unlink_managed "$agent" "$dir/agents/$(basename "$agent")"
        done
        prune_orphans "$dir/agents" "$ZSH/ai/agents"
    done <<EOF
$CLAUDE_DIRS
EOF
    success "Removed agent links"
    overlay_agents uninstall
}
check_agents() {
    while IFS= read -r dir; do
        for agent in "$ZSH"/ai/agents/*.md; do
            check_link "$agent" "$dir/agents/$(basename "$agent")"
        done
        check_orphans "$dir/agents" "$ZSH/ai/agents"
    done <<EOF
$CLAUDE_DIRS
EOF
    overlay_agents check
}

# overlay_agents <mode>: the overlays' agents, beside this repo's, whose names this repo's claim first.
overlay_agents() {
    overlay_link "$1" 'ai/agents/*.md' agents "$(claude_subdirs agents)" "$ZSH/ai/agents"
}

install_skills() {
    while IFS= read -r target; do
        mkdir -p "$target"
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            link "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$ZSH/ai/skills"
        success "Linked skills into $target"
    done <<EOF
$(skill_target_dirs)
EOF
}
uninstall_skills() {
    while IFS= read -r target; do
        [ -d "$target" ] || continue
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            unlink_managed "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$ZSH/ai/skills"
    done <<EOF
$(skill_target_dirs)
EOF
    success "Removed skill links"
}
check_skills() {
    while IFS= read -r target; do
        for skill in "$ZSH"/ai/skills/*/; do
            skill="${skill%/}"
            check_link "$skill" "$target/$(basename "$skill")"
        done
        check_orphans "$target" "$ZSH/ai/skills"
    done <<EOF
$(skill_target_dirs)
EOF
}

# rig ships its own agent skills under <checkout>/skills/ and links none of them;
# this is the linker. Same targets and the same prune rules as the shipped skills,
# with rig's skills/ as the source dir, so each prune touches only its own links.
# A machine without rig has nothing to link and is not drifted.
install_rig_skills() {
    root="$(rig_root)" || { info "No rig checkout on this machine - no rig skills to link"; return 0; }
    [ -d "$root/skills" ] || { info "rig at $root ships no skills yet - run rig update"; return 0; }
    while IFS= read -r target; do
        mkdir -p "$target"
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            link "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$root/skills"
        success "Linked rig skills from $root into $target"
    done <<EOF
$(skill_target_dirs)
EOF
}
uninstall_rig_skills() {
    root="$(rig_root)" || return 0
    while IFS= read -r target; do
        [ -d "$target" ] || continue
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            unlink_managed "$skill" "$target/$(basename "$skill")"
        done
        prune_orphans "$target" "$root/skills"
    done <<EOF
$(skill_target_dirs)
EOF
    success "Removed rig skill links"
}
check_rig_skills() {
    root="$(rig_root)" || { info "No rig checkout on this machine - no rig skills expected"; return 0; }
    [ -d "$root/skills" ] || return 0
    while IFS= read -r target; do
        for skill in "$root"/skills/*/; do
            skill="${skill%/}"
            [ -d "$skill" ] || continue
            check_link "$skill" "$target/$(basename "$skill")"
        done
        check_orphans "$target" "$root/skills"
    done <<EOF
$(skill_target_dirs)
EOF
}

# Overlays ship four kinds of entry, each linked by name: skills (ai/skills/*/, for a skill whose
# text names something private), Bruno collections (bruno/*/, into ~/bruno, so Bruno opens every
# overlay's from one home), rules (ai/rules/*.md, guidance Claude Code reads beside CLAUDE.md) and
# agents (ai/agents/*.md, beside this repo's). A link is named after its entry, so a name shipped
# from two places would have one silently replace the other: a name this repo, rig or an earlier
# overlay already ships is not linked. Install warns and carries on, so one clash cannot stop the
# sync that runs it; --check fails on it.

# overlay_link <install|uninstall|check> <pattern> <kind> <targets> [claimant...]: link the entries
# of an entries row (see overlay_entries) into each target folder, one per line, and prune the
# links into the overlays' folder of that pattern whose source is gone. <kind>, plural, names them
# in messages. Variables are prefixed ol_, since sh has no local.
overlay_link() {
    ol_mode="$1"; ol_pattern="$2"; ol_kind="$3"; ol_targets="$4"; shift 4
    ol_entries="$(overlay_entries "$ol_pattern" "$@")"
    ol_folder="${ol_pattern%/}"; ol_folder="${ol_folder%/*}"
    [ "$ol_mode" = "uninstall" ] || while IFS="$TAB" read -r ol_entry ol_clash; do
        [ -n "$ol_clash" ] || continue
        warning "$ol_entry not linked: $ol_clash already ships that name"
        [ "$ol_mode" = "install" ] || CHECK_FAILED=1
    done <<EOF
$ol_entries
EOF
    while IFS= read -r ol_target; do
        [ -n "$ol_target" ] || continue
        [ "$ol_mode" != "uninstall" ] || [ -d "$ol_target" ] || continue
        [ "$ol_mode" != "install" ] || [ -z "$ol_entries" ] || mkdir -p "$ol_target"
        while IFS="$TAB" read -r ol_entry ol_clash; do
            [ -n "$ol_entry" ] || continue
            ol_link="$ol_target/${ol_entry##*/}"
            case $ol_mode in
                install) [ -n "$ol_clash" ] || link "$ol_entry" "$ol_link" ;;
                check)   [ -n "$ol_clash" ] || check_link "$ol_entry" "$ol_link" ;;
                # A refused name may still hold a link install made before the overlays were
                # reordered; it is ours only if it points here.
                uninstall) if [ -z "$ol_clash" ] || is_link_to "$ol_entry" "$ol_link"; then unlink_managed "$ol_entry" "$ol_link"; fi ;;
            esac
        done <<EOF
$ol_entries
EOF
        if [ "$ol_mode" = "check" ]; then
            each_overlay_orphans "$ol_target" check_orphans "$ol_folder"
        else
            each_overlay_orphans "$ol_target" prune_orphans "$ol_folder"
        fi
        [ "$ol_mode" != "install" ] || [ -z "$ol_entries" ] || success "Linked overlay $ol_kind into $ol_target"
    done <<EOF
$ol_targets
EOF
    [ "$ol_mode" != "uninstall" ] || success "Removed overlay $ol_kind links"
}

# each_overlay_orphans <dir> <prune_orphans|check_orphans> <folder>: run it against <folder> in
# every overlay, including one that is gone, so the links into it are still found.
each_overlay_orphans() {
    [ -n "$OVERLAYS" ] || return 0
    while IFS= read -r overlay; do
        "$2" "$1" "$overlay/$3"
    done <<EOF
$OVERLAYS
EOF
}

# claude_subdirs <name>: <name> in every Claude config folder, one per line.
claude_subdirs() {
    while IFS= read -r dir; do
        echo "$dir/$1"
    done <<EOF
$CLAUDE_DIRS
EOF
}

# overlay_skills <mode>: the overlays' skills, whose names this repo's and rig's claim first.
overlay_skills() {
    rig_skills=""
    root="$(rig_root)" && rig_skills="$root/skills"
    overlay_link "$1" 'ai/skills/*/' skills "$(skill_target_dirs)" "$ZSH/ai/skills" ${rig_skills:+"$rig_skills"}
}
install_overlay_skills()   { overlay_skills install; }
uninstall_overlay_skills() { overlay_skills uninstall; }
check_overlay_skills()     { overlay_skills check; }

# No rule ships from this repo: its own guidance is CLAUDE.md.
install_rules()   { overlay_link install 'ai/rules/*.md' rules "$(claude_subdirs rules)"; }
uninstall_rules() { overlay_link uninstall 'ai/rules/*.md' rules "$(claude_subdirs rules)"; }
check_rules()     { overlay_link check 'ai/rules/*.md' rules "$(claude_subdirs rules)"; }

# No collection lives in this public repo, so nothing of this repo's own claims a name.
install_bruno()   { overlay_link install 'bruno/*/' "Bruno collections" "$BRUNO_DIR"; }
uninstall_bruno() { overlay_link uninstall 'bruno/*/' "Bruno collections" "$BRUNO_DIR"; }
check_bruno()     { overlay_link check 'bruno/*/' "Bruno collections" "$BRUNO_DIR"; }

# Settings are merged, not linked: each folder's settings.json also holds machine-local state.
install_settings() {
    while IFS= read -r dir; do
        mkdir -p "$dir"
        if [ -f "$dir/settings.json" ]; then
            cp "$dir/settings.json" "$dir/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
        fi
        if reconcile_settings merge "$dir/settings.json" "$SETTINGS_FRAGMENT" "$HOOK_BIN"; then
            success "Merged ai/claude/settings.json into $dir/settings.json"
        fi
    done <<EOF
$CLAUDE_DIRS
EOF
}
uninstall_settings() {
    info "Settings are merged, not linked; nothing to remove from any settings.json"
}
check_settings() {
    while IFS= read -r dir; do
        # The drift lines name keys, not files, so say which folder they were about.
        if ! reconcile_settings check "$dir/settings.json" "$SETTINGS_FRAGMENT" "$HOOK_BIN"; then
            warning "$dir/settings.json is out of line with ai/claude/settings.json"
            CHECK_FAILED=1
        fi
        check_hooks_run "$dir/settings.json"
    done <<EOF
$CLAUDE_DIRS
EOF
}

# check_hooks_run <settings file>: run each exec-form hook of ours there (see
# settings-reconcile.sh) that Claude Code would run before a Bash call, whichever checkout it
# points at, on a harmless one, as Claude Code would spawn it, and fail the check on one that
# does not exit 0: a script or a node that is not found blocks every call. Hooks for other events
# or tools are not run, since a harmless Bash call says nothing about what they would do. This
# runs with this shell's PATH, which may hold more than an app's.
check_hooks_run() {
    [ -f "$1" ] && jq empty "$1" > /dev/null 2>&1 || return 0
    hook_argvs="$(jq -r --argjson programs "$(settings_bin_programs "$HOOK_BIN")" "$SETTINGS_SPEC_JQ"'
        [(.hooks.PreToolUse // []) | arrays
         | map(select(type == "object"
             and ((.matcher // "" | if . == "" or . == "*" then ".*" else . end) as $m
                  | try ("Bash" | test("^(\($m))$")) catch false)))
         | ours_in($programs)[] | select((.args | type) == "array")
         | [.command] + .args | @sh] | unique[]' "$1")"
    [ -n "$hook_argvs" ] || return 0
    while IFS= read -r hook_argv; do
        if (eval "set -- $hook_argv"
            printf '%s' '{"tool_name":"Bash","tool_input":{"command":"true"}}' | "$@") > /dev/null 2>&1; then
            success "hook runs: $hook_argv"
        else
            error "hook does not run: $hook_argv (in $1)"
            CHECK_FAILED=1
        fi
    done <<EOF
$hook_argvs
EOF
}

# Copy the managed keys from ~/.claude's live file back into the repo fragment. Only ~/.claude:
# the extra folders get the same keys from the fragment, so they are not a second source.
export_settings() {
    reconcile_settings export "$SETTINGS_FILE" "$SETTINGS_FRAGMENT" "$HOOK_BIN" || exit 1
    success "Wrote managed keys from $SETTINGS_FILE to ai/claude/settings.json (review with git diff)"
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

MODE=install
INSTALL_CLAUDE_MD=true
INSTALL_AGENTS=true
INSTALL_RULES=true
INSTALL_SKILLS=true
INSTALL_RIG_SKILLS=true
INSTALL_OVERLAY_SKILLS=true
INSTALL_BRUNO=true
INSTALL_SETTINGS=true

disable_all() {
    INSTALL_CLAUDE_MD=false
    INSTALL_AGENTS=false
    INSTALL_RULES=false
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
    echo "links each overlay's agents beside this repo's and its rules (<overlay>/ai/rules/*.md)"
    echo "into ~/.claude/rules, links each overlay's Bruno collections (<overlay>/bruno/) into ~/bruno, and merges"
    echo "ai/claude/settings.json into ~/.claude/settings.json. Every extra Claude config folder"
    echo "an overlay names in <overlay>/ai/claude/config-dirs gets the same as ~/.claude."
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
    echo "  --agents-only          Only agent files, this repo's and the overlays'"
    echo "  --rules-only           Only the rules overlays ship (<overlay>/ai/rules/*.md)"
    echo "  --skills-only          Only skills"
    echo "  --rig-skills-only      Only the skills rig ships (RIG_ROOT, else D:/rig, C:/rig, ~/rig)"
    echo "  --overlay-skills-only  Only the skills overlays ship (<overlay>/ai/skills/)"
    echo "  --bruno-only           Only the Bruno collections overlays ship (<overlay>/bruno/)"
    echo "  --settings-only        Only settings merge"
    echo "  --no-claude-md         Skip CLAUDE.md"
    echo "  --no-agents            Skip agents"
    echo "  --no-rules             Skip the rules overlays ship"
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
        --rules-only)          disable_all; INSTALL_RULES=true ;;
        --skills-only)         disable_all; INSTALL_SKILLS=true ;;
        --rig-skills-only)     disable_all; INSTALL_RIG_SKILLS=true ;;
        --overlay-skills-only) disable_all; INSTALL_OVERLAY_SKILLS=true ;;
        --bruno-only)          disable_all; INSTALL_BRUNO=true ;;
        --settings-only)       disable_all; INSTALL_SETTINGS=true ;;
        --no-claude-md)        INSTALL_CLAUDE_MD=false ;;
        --no-agents)           INSTALL_AGENTS=false ;;
        --no-rules)            INSTALL_RULES=false ;;
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

# A listed overlay that is gone fails an install or a check rather than dropping all it carries.
# Uninstall carries on, since its prune needs only the overlay's path to take the links into it.
# Export reads ~/.claude alone, so it has no use for the overlays or the extra folders.
if [ "$MODE" = "export" ]; then
    :
elif overlays_load "$ZSH"; then
    resolve_claude_dirs
elif [ "$MODE" != "uninstall" ]; then
    exit 1
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

case $MODE in
    install)   info "Installing AI tooling from ${ZSH}…" ;;
    uninstall) info "Removing AI tooling links…" ;;
    check)     info "Checking AI tooling links…" ;;
    export)    info "Exporting settings…" ;;
esac

[ "$INSTALL_CLAUDE_MD" = "true" ] && ${MODE}_claude_md
[ "$INSTALL_AGENTS" = "true" ]    && ${MODE}_agents
[ "$INSTALL_RULES" = "true" ]     && ${MODE}_rules
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
    [ -n "$OVERLAYS" ] && while IFS= read -r overlay; do
        if sh "$ZSH/ai/secrets/check-encrypted.sh" "$overlay/ai/secrets"; then
            success "$overlay/ai/secrets: all files encrypted"
        else
            CHECK_FAILED=1
        fi
    done <<EOF
$OVERLAYS
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
