#!/bin/sh

# Suite for handoffTitles and matchingProject in ai/skills/hf-t3-handoff/t3.mjs,
# the parts of the T3 handoff that are functions of their arguments. Everything
# else in that script talks to a running T3 Code server and is not run here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

module="$REPO_ROOT/ai/skills/hf-t3-handoff/t3.mjs"

# titles <current title> [key description]: prints "<rename>|<next>".
titles() {
    # All of it goes through the environment: with no argv[1] the module only exports.
    T3_MODULE="$module" T3_TITLE="$1" T3_KEY="$2" T3_DESCRIPTION="$3" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { handoffTitles } = await import(pathToFileURL(process.env.T3_MODULE).href);
        const { T3_TITLE, T3_KEY, T3_DESCRIPTION } = process.env;
        const { rename, next } = handoffTitles(T3_TITLE, T3_KEY ? { key: T3_KEY, description: T3_DESCRIPTION } : undefined);
        console.log((rename ?? '') + '|' + next);
    "
}

assert_eq "a free-form title is renamed to the standard and continues at 1" \
    "RIG - [KTLO-1580] Dependabot sweep|RIG - [KTLO-1580] Dependabot sweep 1" \
    "$(titles 'Fix the dependabot alerts' KTLO-1580 'Dependabot sweep')"
assert_eq "a standard title without a count continues at 1" \
    "|RIG - [rig#13] Automate handoff 1" \
    "$(titles 'RIG - [rig#13] Automate handoff' other 'ignored')"
assert_eq "a standard title counts up" \
    "|RIG - [rig#13] Automate handoff 3" \
    "$(titles 'RIG - [rig#13] Automate handoff 2')"
assert_eq "the count passes 9" \
    "|RIG - [rig#13] Automate handoff 10" \
    "$(titles 'RIG - [rig#13] Automate handoff 9')"
assert_eq "with no work, an unnumbered title gains a 2" \
    "|Automate Handoff 2" \
    "$(titles 'Automate Handoff')"
assert_eq "with no work, a numbered title counts up" \
    "|Automate Handoff 3" \
    "$(titles 'Automate Handoff 2')"
assert_eq "surrounding whitespace is dropped" \
    "|Tidy 2" \
    "$(titles '  Tidy  ')"

# match <project json> <candidates json>: prints the matching candidate's id, or "none".
match() {
    T3_MODULE="$module" T3_PROJECT="$1" T3_CANDIDATES="$2" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { matchingProject } = await import(pathToFileURL(process.env.T3_MODULE).href);
        const { T3_PROJECT, T3_CANDIDATES } = process.env;
        console.log(matchingProject(JSON.parse(T3_PROJECT), JSON.parse(T3_CANDIDATES))?.id ?? 'none');
    "
}

# project <id> <title> [canonical key]: one project as T3 lists it.
project() {
    if [ -n "$3" ]; then
        printf '{"id":"%s","title":"%s","repositoryIdentity":{"canonicalKey":"%s"}}' "$1" "$2" "$3"
    else
        printf '{"id":"%s","title":"%s","repositoryIdentity":null}' "$1" "$2"
    fi
}

here="$(project here dotfiles github.com/hugoforte/dotfiles)"

assert_eq "the project with the same repository matches, whatever its title"     "there"     "$(match "$here" "[$(project other rig github.com/hugoforte/rig),$(project there dots github.com/hugoforte/dotfiles)]")"
assert_eq "a title alone is no match"     "none"     "$(match "$here" "[$(project there dotfiles github.com/someone/dotfiles),$(project bare dotfiles)]")"
assert_eq "among several clones, the one titled like this project matches"     "second"     "$(match "$here" "[$(project first dotfiles-spike github.com/hugoforte/dotfiles),$(project second dotfiles github.com/hugoforte/dotfiles)]")"
assert_eq "several clones and no title to tell them apart is no match"     "none"     "$(match "$here" "[$(project first a github.com/hugoforte/dotfiles),$(project second b github.com/hugoforte/dotfiles)]")"
assert_eq "a project with no repository matches nothing"     "none"     "$(match "$(project here scratch)" "[$(project there scratch)]")"

# call <expression>: evaluates an expression over the module's exports (as `t3`) and
# prints its value, or "error: <message>" when it throws.
call() {
    T3_MODULE="$module" T3_EXPRESSION="$1" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const t3 = await import(pathToFileURL(process.env.T3_MODULE).href);
        const AsyncFunction = (async () => {}).constructor;
        try {
            console.log(await new AsyncFunction('t3', 'return (' + process.env.T3_EXPRESSION + ')')(t3));
        } catch (error) {
            console.log('error: ' + error.message);
        }
    "
}

# The examples live under the temp directory, so they are absolute on every platform.
root="$(cd "${TMPDIR:-/tmp}" && pwd -W 2>/dev/null || pwd)"
# native <part...>: a folder under the root, as Node spells it in a message.
native() {
    call "(await import('node:path')).resolve(String.raw\`$root\`, ...'$*'.split(' '))"
}
projects="[{id:'example',title:'example',workspaceRoot:String.raw\`$root\\projects\\example\`},{id:'other',title:'other',workspaceRoot:'$root/projects/other/'}]"

assert_eq "--project finds the project whose workspace root is the folder" \
    "example" \
    "$(call "t3.projectForFolder(String.raw\`$root\\projects\\example\`, $projects).id")"
assert_eq "--project matches with either slash and a trailing one" \
    "other" \
    "$(call "t3.projectForFolder('$root/projects/other', $projects).id")"
assert_eq "--project matches without case on Windows" \
    "example" \
    "$(call "t3.projectForFolder(process.platform === 'win32' ? String.raw\`$root\\PROJECTS\\Example\` : String.raw\`$root/projects/example\`, $projects).id")"
assert_eq "--project for a folder T3 has no project for says how to add one" \
    "error: T3 Code has no project for $(native projects missing)" \
    "$(call "t3.projectForFolder(String.raw\`$root\\projects\\missing\`, $projects)")"
assert_eq "--project for a folder with two T3 projects names both" \
    "error: T3 Code has 2 projects for $(native projects example): \"example\" (example), \"copy\" (copy)" \
    "$(call "t3.projectForFolder(String.raw\`$root\\projects\\example\`, [...$projects, {id:'copy',title:'copy',workspaceRoot:String.raw\`$root\\projects\\example\`}])")"

settings="{providers:{codex:{enabled:false}},providerInstances:{claudeAgent:{driver:'claudeAgent',displayName:'Claude'},claudeAgent_work:{driver:'claudeAgent',displayName:'Claude Work',enabled:true,config:{homePath:'~/.claude-work'}},claudeAgent_old:{driver:'claudeAgent',displayName:'Claude Old',enabled:false},codex_spare:{driver:'codex',config:{enabled:true}}}}"

# instance <id> [current instance id]: prints "<id>|<display name>|<driver>", or the error.
instance() {
    call "(({ id, displayName, driver }) => [id, displayName, driver].join('|'))(t3.providerInstance('$1', $settings, '${2:-}' || undefined))"
}

assert_eq "--provider finds an enabled instance and its display name" \
    "claudeAgent_work|Claude Work|claudeAgent" \
    "$(instance claudeAgent_work claudeAgent)"
assert_eq "--provider names an instance with no display name by its id" \
    "codex_spare|codex_spare|codex" \
    "$(instance codex_spare)"
assert_eq "--provider for an unknown instance lists the enabled ones" \
    "error: T3 Code has no provider instance \"claudeAgent_typo\"; the enabled ones are claudeAgent (Claude), claudeAgent_work (Claude Work), codex_spare (codex_spare)" \
    "$(instance claudeAgent_typo)"
assert_eq "--provider for a disabled instance lists the enabled ones" \
    "error: provider instance \"claudeAgent_old\" (Claude Old) is disabled in T3 Code; the enabled ones are claudeAgent (Claude), claudeAgent_work (Claude Work), codex_spare (codex_spare)" \
    "$(instance claudeAgent_old)"
assert_eq "--provider for a default instance its driver turned off says it is disabled" \
    "error: provider instance \"codex\" (codex) is disabled in T3 Code; the enabled ones are claudeAgent (Claude), claudeAgent_work (Claude Work), codex_spare (codex_spare)" \
    "$(instance codex)"
assert_eq "--provider refuses an instance of another driver than the thread's model" \
    "error: provider instance \"codex_spare\" runs codex, and this thread's model runs on claudeAgent" \
    "$(instance codex_spare claudeAgent_work)"

current="{projectId:'here',branch:'feature',worktreePath:null,modelSelection:{instanceId:'claudeAgent',model:'claude-model',options:[{id:'effort',value:'medium'}]}}"

# destination <project expression>: prints the next thread's "<projectId>|<branch>|<worktreePath>|<place>".
destination() {
    call "(({ projectId, branch, worktreePath, place }) => [projectId, branch, worktreePath, place].join('|'))(await t3.destination(undefined, $current, undefined, $1))"
}

assert_eq "without --project the next thread keeps this project and branch" \
    "here|feature||feature" \
    "$(destination undefined)"
assert_eq "--project for this thread's own project keeps the branch" \
    "here|feature||D:/projects/here, feature" \
    "$(destination "{id:'here',workspaceRoot:'D:/projects/here'}")"
assert_eq "--project for another project starts in its checkout" \
    "there|||D:/projects/there" \
    "$(destination "{id:'there',workspaceRoot:'D:/projects/there'}")"

assert_eq "without --provider the model selection is this thread's, untouched" \
    "true" \
    "$(call "(() => { const s = ($current).modelSelection; return t3.modelSelectionOn(s, undefined) === s; })()")"
assert_eq "--provider keeps the model and its options and changes only the instance" \
    '{"instanceId":"claudeAgent_work","model":"claude-model","options":[{"id":"effort","value":"medium"}]}' \
    "$(call "JSON.stringify(t3.modelSelectionOn(($current).modelSelection, { id: 'claudeAgent_work' }))")"

# cli <args...>: runs t3.mjs and prints the first line it wrote to stderr. Each case
# here is refused while the arguments are read, before anything reaches T3 Code.
cli() {
    node "$module" "$@" 2>&1 >/dev/null | head -n 1
}

assert_eq "--project needs a folder" \
    "t3: --project needs a value" \
    "$(cli continue --prompt-file x --project)"
assert_eq "--provider needs an instance id" \
    "t3: --provider needs a value" \
    "$(cli check --provider --dry-run)"
assert_eq "--project and --to do not go together" \
    "t3: --project and --provider choose on this computer, so they do not go with --to" \
    "$(cli continue --prompt-file x --to elsewhere --project .)"

assert_summary "t3-handoff"
