#!/bin/sh

# Suite for ai/skills/hf-t3-handoff/t3.mjs: the parts of the T3 handoff that are
# functions of their arguments, such as the titles, the project matching and
# where T3 Code is installed on each platform. Everything
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
# The separator Node reads on this platform: \ on Windows, where pwd -W answered, / elsewhere.
case "$root" in [A-Za-z]:*) s='\' ;; *) s='/' ;; esac
# native <part...>: a folder under the root, as Node spells it in a message.
native() {
    call "(await import('node:path')).resolve(String.raw\`$root\`, ...'$*'.split(' '))"
}
example="String.raw\`$root${s}projects${s}example\`"
# Object literals go through variables: macOS's /bin/sh (bash 3.2) brace-expands a {a,b} written
# inside "$( ... "..." )" when no whitespace separates the comma from the braces, which would
# split one before Node saw it.
projects="[{id:'example',title:'example',workspaceRoot:$example},{id:'other',title:'other',workspaceRoot:'$root/projects/other/'}]"
copy="{id:'copy',title:'copy',workspaceRoot:$example}"

assert_eq "--project finds the project whose workspace root is the folder" \
    "example" \
    "$(call "t3.projectForFolder($example, $projects).id")"
assert_eq "--project matches with either slash and a trailing one" \
    "other" \
    "$(call "t3.projectForFolder('$root/projects/other', $projects).id")"
if [ "$s" = '\' ]; then
    assert_eq "--project matches without case on Windows" \
        "example" \
        "$(call "t3.projectForFolder(String.raw\`$root\\PROJECTS\\Example\`, $projects).id")"
else
    printf '  SKIP  --project matches without case on Windows: not on Windows\n'
fi
assert_eq "--project for a folder T3 has no project for says how to add one" \
    "error: T3 Code has no project for $(native projects missing)" \
    "$(call "t3.projectForFolder(String.raw\`$root${s}projects${s}missing\`, $projects)")"
assert_eq "--project for a folder with two T3 projects names both" \
    "error: T3 Code has 2 projects for $(native projects example): \"example\" (example), \"copy\" (copy)" \
    "$(call "t3.projectForFolder($example, [...$projects, $copy])")"

settings="{providers:{codex:{enabled:false},grok:{enabled:false}},providerInstances:{claudeAgent:{driver:'claudeAgent',displayName:'Claude'},claudeAgent_work:{driver:'claudeAgent',displayName:'Claude Work',enabled:true,config:{homePath:'~/.claude-work'}},claudeAgent_old:{driver:'claudeAgent',displayName:'Claude Old',enabled:false},codex_spare:{driver:'codex',config:{enabled:true}},codex_managed:{driver:'codex',enabled:true,config:{enabled:false}},grok_unset:{driver:'grok'}}}"

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
assert_eq "--provider for an instance whose config turns it off says it is disabled" \
    "error: provider instance \"codex_managed\" (codex_managed) is disabled in T3 Code; the enabled ones are claudeAgent (Claude), claudeAgent_work (Claude Work), codex_spare (codex_spare)" \
    "$(instance codex_managed)"
assert_eq "--provider for an instance that does not say takes its driver's setting" \
    "error: provider instance \"grok_unset\" (grok_unset) is disabled in T3 Code; the enabled ones are claudeAgent (Claude), claudeAgent_work (Claude Work), codex_spare (codex_spare)" \
    "$(instance grok_unset)"
assert_eq "--provider for a thread whose instance is gone skips the driver comparison" \
    "codex_spare|codex_spare|codex" \
    "$(instance codex_spare claudeAgent_removed)"
assert_eq "--provider refuses an instance of another driver than the thread's model" \
    "error: provider instance \"codex_spare\" runs codex, and this thread's model runs on claudeAgent" \
    "$(instance codex_spare claudeAgent_work)"

current="{projectId:'here',branch:'feature',worktreePath:null,modelSelection:{instanceId:'claudeAgent',model:'claude-model',options:[{id:'effort',value:'medium'}]}}"

# destination <project expression>: prints the next thread's "<projectId>|<branch>|<worktreePath>|<place>".
destination() {
    call "(({ projectId, branch, worktreePath, place }) => [projectId, branch, worktreePath, place].join('|'))(await t3.destination(undefined, $current, undefined, $1))"
}

# Through variables, as $copy above.
here_project="{id:'here',workspaceRoot:'D:/projects/here'}"
there_project="{id:'there',workspaceRoot:'D:/projects/there'}"

assert_eq "without --project the next thread keeps this project and branch" \
    "here|feature||feature" \
    "$(destination undefined)"
assert_eq "--project for this thread's own project keeps the branch" \
    "here|feature||D:/projects/here, feature" \
    "$(destination "$here_project")"
assert_eq "--project for another project starts in its checkout" \
    "there|||D:/projects/there" \
    "$(destination "$there_project")"

assert_eq "without --provider the model selection is this thread's, untouched" \
    "true" \
    "$(call "(() => { const s = ($current).modelSelection; return t3.modelSelectionOn(s, undefined) === s; })()")"
assert_eq "--provider keeps the model and its options and changes only the instance" \
    '{"instanceId":"claudeAgent_work","model":"claude-model","options":[{"id":"effort","value":"medium"}]}' \
    "$(call "JSON.stringify(t3.modelSelectionOn(($current).modelSelection, { id: 'claudeAgent_work' }))")"

# app <platform> [T3_EXE]: prints "<exe>|<serverBin>" for that platform.
app() {
    call "(({ exe, serverBin }) => exe + '|' + serverBin)(t3.t3App('$1', { LOCALAPPDATA: String.raw\`C:\\Users\\me\\AppData\\Local\`, ${2:+T3_EXE: String.raw\`$2\`} }))"
}

assert_eq "on Windows T3 Code is the per-user install, its server in resources beside it" \
    'C:\Users\me\AppData\Local\Programs\t3code\T3 Code (Alpha).exe|C:\Users\me\AppData\Local\Programs\t3code\resources\server.asar\apps\server\dist\bin.mjs' \
    "$(app win32)"
assert_eq "on macOS T3 Code is the app bundle, its server in the bundle's app.asar" \
    '/Applications/T3 Code (Alpha).app/Contents/MacOS/T3 Code (Alpha)|/Applications/T3 Code (Alpha).app/Contents/Resources/app.asar/apps/server/dist/bin.mjs' \
    "$(app darwin)"
assert_eq "on macOS T3_EXE moves the server with it" \
    '/Users/me/Applications/T3.app/Contents/MacOS/T3|/Users/me/Applications/T3.app/Contents/Resources/app.asar/apps/server/dist/bin.mjs' \
    "$(app darwin /Users/me/Applications/T3.app/Contents/MacOS/T3)"

assert_eq "a Mac's .local host name is reached without it" \
    "Hugos-MacBook-Pro" \
    "$(call "t3.reachableName('Hugos-MacBook-Pro.local')")"
assert_eq "a host name without .local is reached as it is" \
    "ZENBOOK" \
    "$(call "t3.reachableName('ZENBOOK')")"

# Statuses as `tailscale status --json` prints them, cut to the fields read.
tailnet="{Self:{HostName:'Hugos-MacBook-Pro',DNSName:'macbook.tail0.ts.net.'},Peer:{a:{HostName:'HugoDesktop',DNSName:'hugodesktop.tail0.ts.net.'},b:{HostName:'zenbook',DNSName:''}}}"
no_dns="{Self:{HostName:'Hugos-MacBook-Pro',DNSName:''}}"

assert_eq "token names this computer by its MagicDNS name when Tailscale has one" \
    "macbook" \
    "$(call "t3.tokenName($tailnet, 'Hugos-MacBook-Pro.local')")"
assert_eq "token names this computer by its Tailscale host name without MagicDNS" \
    "Hugos-MacBook-Pro" \
    "$(call "t3.tokenName($no_dns, 'other')")"
assert_eq "token names this computer by its host name without Tailscale" \
    "Hugos-MacBook-Pro" \
    "$(call "t3.tokenName(undefined, 'Hugos-MacBook-Pro.local')")"
assert_eq "the peers are named as the Tailscale name of each" \
    "hugodesktop,zenbook" \
    "$(call "t3.tailscalePeerNames($tailnet).join(',')")"

# fetch_error <cause code>: a rejection shaped like Node's fetch's.
fetch_error() {
    printf "Object.assign(new TypeError('fetch failed'), { cause: Object.assign(new Error('x'), { code: '%s' }) })" "$1"
}

assert_eq "a name that is not found does not resolve" \
    "true" \
    "$(call "t3.doesNotResolve($(fetch_error ENOTFOUND))")"
assert_eq "a name the resolver could not answer for yet does not resolve" \
    "true" \
    "$(call "t3.doesNotResolve($(fetch_error EAI_AGAIN))")"
assert_eq "a refused connection is not a name that does not resolve" \
    "false" \
    "$(call "t3.doesNotResolve($(fetch_error ECONNREFUSED))")"

# unresolved <peers expression>: prints "<problem>|<fix>".
unresolved() {
    call "(({ message, fix }) => message + '|' + fix)(t3.unresolvedOrigin('macbook-pro', 'http://Hugos-MacBook-Pro:3773', $1))"
}

assert_eq "an origin that does not resolve says so and lists the Tailscale peers" \
    "hugos-macbook-pro, the host in macbook-pro's origin http://Hugos-MacBook-Pro:3773, does not resolve on this computer|Change the origin in that entry to a name this computer resolves. Tailscale sees: hugodesktop, zenbook." \
    "$(unresolved "['hugodesktop', 'zenbook']")"
assert_eq "an origin that does not resolve, without Tailscale, says to use a name that does" \
    "hugos-macbook-pro, the host in macbook-pro's origin http://Hugos-MacBook-Pro:3773, does not resolve on this computer|Change the origin in that entry to a name or address this computer resolves, such as its Tailscale name." \
    "$(unresolved undefined)"

assert_eq "the live thread is picked over the row T3 keeps for an imported session" \
    "bb2e44fc" \
    "$(call "t3.sessionThread('s1', ['import:claudeAgent_claude_kealu:s1', 'bb2e44fc'])")"
assert_eq "an imported session's row is the thread when it is the only one" \
    "import:claudeAgent:s1" \
    "$(call "t3.sessionThread('s1', ['import:claudeAgent:s1'])")"
assert_eq "two live threads for one session are named" \
    "error: expected one T3 thread for Claude session s1, found 2: a, b" \
    "$(call "t3.sessionThread('s1', ['a', 'import:x:s1', 'b'])")"
assert_eq "no thread for the session says none was found" \
    "error: expected one T3 thread for Claude session s1, found 0" \
    "$(call "t3.sessionThread('s1', [])")"

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
assert_eq "--thread needs a thread id" \
    "t3: --thread needs a value" \
    "$(cli check --thread)"
assert_eq "--project and --to do not go together" \
    "t3: --project and --provider choose on this computer, so they do not go with --to" \
    "$(cli continue --prompt-file x --to elsewhere --project .)"

assert_summary "t3-handoff"
