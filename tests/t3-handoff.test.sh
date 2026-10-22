#!/bin/sh

# Suite for ai/skills/hf-t3-handoff/t3.mjs: the parts of the T3 handoff that are
# functions of their arguments, such as the titles, the project matching and
# where T3 Code's command line is on each platform. Everything
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

assert_eq "an https remote is keyed by host and path, without .git" \
    "github.com/hugoforte/dotfiles-private" \
    "$(call "t3.remoteKey('https://github.com/HugoForte/dotfiles-private.git')")"
assert_eq "an scp-style remote is keyed the same" \
    "github.com/hugoforte/dotfiles-private" \
    "$(call "t3.remoteKey('git@github.com:hugoforte/dotfiles-private.git')")"

# A checkout with an origin, and one with no remote, for when T3 has not said a project's repository.
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
git init -q "$work/with-origin" && git -C "$work/with-origin" remote add origin https://github.com/hugoforte/dotfiles-private.git
git init -q "$work/no-remote"
# As Node spells them on this platform.
with_origin="$(cd "$work/with-origin" && (pwd -W 2>/dev/null || pwd))"
no_remote="$(cd "$work/no-remote" && (pwd -W 2>/dev/null || pwd))"
this_computer="$(call "t3.reachableName((await import('node:os')).hostname())")"

# to_mac <this project> <the mac's projects>: prints "<projectId>|<place>" for --to the mac, or the error.
to_mac() {
    call "(({ projectId, place }) => projectId + '|' + place)(await t3.destination({ get: async () => ({ projects: [$1] }) }, $current, { name: 'a-macbook-pro', server: {}, projects: $2 }))"
}

# Through variables, as $copy above.
unresolved_here="{id:'here',title:'dotfiles-private',workspaceRoot:String.raw\`$with_origin\`,repositoryIdentity:null}"
no_remote_here="{id:'here',title:'scratch',workspaceRoot:String.raw\`$no_remote\`,repositoryIdentity:null}"
mac_clone="{id:'mac',title:'dotfiles-private',workspaceRoot:'/Users/me/dotfiles-private',repositoryIdentity:{canonicalKey:'github.com/hugoforte/dotfiles-private'}}"
mac_unresolved="{id:'pending',title:'dotfiles-private',workspaceRoot:'/Users/me/dotfiles-private',repositoryIdentity:null}"

assert_eq "--to finds the project by this checkout's origin when T3 has not said its repository" \
    "mac|a-macbook-pro, /Users/me/dotfiles-private" \
    "$(to_mac "$unresolved_here" "[$mac_clone]")"
assert_eq "--to for a project with no remote names this computer, not the destination" \
    "error: project \"scratch\" has no git remote on $this_computer to find it by: $no_remote has neither an upstream nor an origin" \
    "$(to_mac "$no_remote_here" "[$mac_clone]")"
assert_eq "--to with no match names the projects there whose repository T3 did not say" \
    "error: a-macbook-pro has no one project for github.com/hugoforte/dotfiles-private, the repository of \"dotfiles-private\"; T3 Code there did not say the repository of \"dotfiles-private\"" \
    "$(to_mac "$unresolved_here" "[$mac_unresolved]")"

# Reads the shell twice: T3 says the repository only on the second read, as when its cache was cold.
warming="{ reads: 0, async get() { this.reads++; return { projects: [this.reads > 1 ? $mac_clone : $mac_unresolved] }; } }"

assert_eq "the projects there are read again until T3 says their repositories" \
    "mac" \
    "$(call "(await t3.readProjectsWithRepositories($warming, { delayMs: 1 }))[0].id")"

assert_eq "without --provider the model selection is this thread's, untouched" \
    "true" \
    "$(call "(() => { const s = ($current).modelSelection; return t3.modelSelectionOn(s, undefined) === s; })()")"
assert_eq "--provider keeps the model and its options and changes only the instance" \
    '{"instanceId":"claudeAgent_work","model":"claude-model","options":[{"id":"effort","value":"medium"}]}' \
    "$(call "JSON.stringify(t3.modelSelectionOn(($current).modelSelection, { id: 'claudeAgent_work' }))")"

# cli_path <platform> <T3 home> [T3CODE_CLI_PATH]: prints the T3 command line t3.mjs runs.
cli_path() {
    call "t3.t3Cli('$1', { ${3:+T3CODE_CLI_PATH: String.raw\`$3\`} }, String.raw\`$2\`)"
}

assert_eq "on macOS the T3 command line is the launcher in T3's home" \
    '/Users/me/.t3/bin/t3' \
    "$(cli_path darwin /Users/me/.t3)"
assert_eq "on Windows the launcher is a .cmd" \
    'C:\Users\me\.t3\bin\t3.cmd' \
    "$(cli_path win32 'C:\Users\me\.t3')"
assert_eq "T3CODE_CLI_PATH names the launcher instead" \
    '/opt/t3/t3' \
    "$(cli_path darwin /Users/me/.t3 /opt/t3/t3)"

# strategy <next>: prints the launch's workspace strategy as JSON.
strategy() {
    call "JSON.stringify(t3.workspaceStrategy($1))"
}

# Through variables, as $copy above.
in_worktree="{branch:'feature',worktreePath:'/w/here'}"
on_branch="{branch:'feature',worktreePath:null}"
in_checkout="{branch:null,worktreePath:null}"

assert_eq "a thread in a worktree continues in that worktree" \
    '{"type":"existing_worktree","worktreePath":"/w/here","branch":"feature"}' \
    "$(strategy "$in_worktree")"
assert_eq "a thread on a branch of the project checkout continues there on that branch" \
    '{"type":"root","branch":"feature"}' \
    "$(strategy "$on_branch")"
assert_eq "a thread with neither continues in the project checkout" \
    '{"type":"root"}' \
    "$(strategy "$in_checkout")"

# rpc <exit>: prints what an RPC answer comes to, or the error.
rpc() {
    call "JSON.stringify(t3.rpcValue('orchestration.launchThread', $1))"
}

success="{_tag:'Success',value:{threadId:'t'}}"
died="{_tag:'Failure',cause:[{_tag:'Die',defect:'Missing key at [\"commandId\"]'}]}"
failed="{_tag:'Failure',cause:[{_tag:'Fail',error:{_tag:'ThreadManagementProviderInstanceDisabledError',message:'claudeAgent_old is disabled'}}]}"

assert_eq "an RPC success is its value" \
    '{"threadId":"t"}' \
    "$(rpc "$success")"
assert_eq "an RPC defect says what the server could not read" \
    'error: orchestration.launchThread failed: Missing key at ["commandId"]' \
    "$(rpc "$died")"
assert_eq "an RPC failure says the server's message" \
    'error: orchestration.launchThread failed: claudeAgent_old is disabled' \
    "$(rpc "$failed")"

# frames <frame...>: prints what an RPC over a socket that answers with these frames comes to, or the
# error. A frame is JSON, or `close` for the socket closing; the call times out after 200 ms.
frames() {
    # Frames are separated by newlines, since the module reads any argv[1] as its own path.
    T3_MODULE="$module" T3_FRAMES="$(printf '%s\n' "$@")" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const t3 = await import(pathToFileURL(process.env.T3_MODULE).href);
        const frames = process.env.T3_FRAMES.split('\n').filter(Boolean);
        class Socket extends EventTarget {
            send() {
                for (const frame of frames) {
                    if (frame === 'close') this.dispatchEvent(Object.assign(new Event('close'), { code: 1006, reason: '' }));
                    else this.dispatchEvent(Object.assign(new Event('message'), { data: frame }));
                }
            }
        }
        const socket = new Socket();
        const answer = t3.rpcOver(socket, 'http://here:3773', 'orchestration.launchThread', {}, 200);
        socket.dispatchEvent(new Event('open'));
        try {
            console.log(JSON.stringify(await answer));
        } catch (error) {
            console.log('error: ' + error.message);
        }
    "
}

answer='{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success","value":"done"}}'
other='{"_tag":"Exit","requestId":"2","exit":{"_tag":"Success","value":"not ours"}}'

assert_eq "an RPC answers with its request's exit" '"done"' "$(frames "$answer")"
assert_eq "an exit for another request is not the answer" '"done"' "$(frames "$other" "$answer")"
assert_eq "a socket closed before the answer fails the call" \
    'error: http://here:3773 closed the WebSocket during orchestration.launchThread (1006)' \
    "$(frames close)"
assert_eq "a defect frame fails the call" \
    'error: http://here:3773 could not take orchestration.launchThread: {"_tag":"Defect","defect":"unknown method"}' \
    "$(frames '{"_tag":"Defect","defect":"unknown method"}')"
assert_eq "a frame that is not JSON fails the call" \
    'error: http://here:3773 answered orchestration.launchThread with a frame that is not JSON: oops' \
    "$(frames oops)"
assert_eq "a call with no answer times out" \
    'error: orchestration.launchThread on http://here:3773 had no answer after 0.2 s' \
    "$(frames)"

# started <status...>: prints whether a thread whose runs have these statuses has started, or the error.
started() {
    runs=""
    for status in "$@"; do runs="$runs{status:'$status'},"; done
    call "t3.runStarted([$runs])"
}

assert_eq "a thread with no run has not started" "false" "$(started)"
assert_eq "a run still being prepared has not started" "false" "$(started preparing)"
assert_eq "a run still starting has not started" "false" "$(started starting)"
assert_eq "a running run has started" "true" "$(started running)"
assert_eq "a run waiting for input has started" "true" "$(started waiting)"
assert_eq "a run that completed has started" "true" "$(started completed)"
assert_eq "the latest run is the one that counts" "false" "$(started completed preparing)"
assert_eq "a run that failed stops the handoff" \
    "error: the new thread's run ended failed before it started" \
    "$(started failed)"

# protocol <environment>: prints what the environment's protocol comes to, or the error.
protocol() {
    call "t3.speaksProtocol('http://workpc:3773', $1)"
}

assert_eq "a server on protocol 2 is spoken to" "true" "$(protocol "{orchestrationProtocolVersion:2}")"
assert_eq "a server that names no protocol is from before protocol 2" \
    "error: T3 Code at http://workpc:3773 speaks orchestration protocol 1, and this script speaks 2" \
    "$(protocol "{serverVersion:'0.0.45'}")"
assert_eq "a newer protocol is refused too" \
    "error: T3 Code at http://workpc:3773 speaks orchestration protocol 3, and this script speaks 2" \
    "$(protocol "{orchestrationProtocolVersion:3}")"

assert_eq "a Mac's .local host name is reached without it" \
    "A-MacBook-Pro" \
    "$(call "t3.reachableName('A-MacBook-Pro.local')")"
assert_eq "a host name without .local is reached as it is" \
    "WORKPC" \
    "$(call "t3.reachableName('WORKPC')")"

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
assert_eq "--ttl takes a count and a unit, which reach a shell on Windows" \
    "t3: --ttl must be a count and a unit such as 365d, not 1d & calc" \
    "$(cli token --ttl '1d & calc')"
assert_eq "--ttl of nothing is refused" \
    "t3: --ttl must be a count and a unit such as 365d, not 0d" \
    "$(cli token --ttl 0d)"
assert_eq "--ttl takes a unit in words, as T3 does" \
    "2 weeks" \
    "$(call "t3.parseArgs(['token', '--ttl', '2 weeks']).flags.ttl")"
assert_eq "--project and --to do not go together" \
    "t3: --project and --provider choose on this computer, so they do not go with --to" \
    "$(cli continue --prompt-file x --to elsewhere --project .)"

assert_summary "t3-handoff"
