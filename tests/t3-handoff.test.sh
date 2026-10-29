#!/bin/sh

# Suite for ai/skills/hf-t3-handoff/t3.mjs: the parts of the T3 handoff that are
# functions of their arguments, such as the titles, the project matching on
# another computer, the --from file and where T3 Code's command line is on each
# platform. Everything else in that script talks to a running T3 Code server and
# is not run here; on this computer the agent's MCP tools do the handoff.

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
    call "(({ projectId, place }) => projectId + '|' + place)(t3.destination($1, { name: 'a-macbook-pro', server: {}, projects: $2 }))"
}

# Object literals go through variables: macOS's /bin/sh (bash 3.2) brace-expands a {a,b} written
# inside "$( ... "..." )" when no whitespace separates the comma from the braces, which would
# split one before Node saw it.
unresolved_here="{id:'here',title:'dotfiles-private',workspaceRoot:String.raw\`$with_origin\`,repositoryIdentity:null}"
no_remote_here="{id:'here',title:'scratch',workspaceRoot:String.raw\`$no_remote\`,repositoryIdentity:null}"
mac_clone="{id:'mac',title:'dotfiles-private',workspaceRoot:'/Users/me/dotfiles-private',repositoryIdentity:{canonicalKey:'github.com/hugoforte/dotfiles-private'}}"
mac_unresolved="{id:'pending',title:'dotfiles-private',workspaceRoot:'/Users/me/dotfiles-private',repositoryIdentity:null}"

said_here="{id:'here',title:'dotfiles-private',workspaceRoot:String.raw\`$no_remote\`,repositoryIdentity:{canonicalKey:'github.com/hugoforte/dotfiles-private'}}"

assert_eq "--to finds the project by the repository T3 said for this one" \
    "mac|a-macbook-pro, /Users/me/dotfiles-private" \
    "$(to_mac "$said_here" "[$mac_clone]")"
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

assert_eq "--to needs a computer" \
    "t3: --to needs a value" \
    "$(cli check --to --from x)"
assert_eq "--to needs --from, which says what this thread is" \
    "t3: --to needs --from, the file of this thread's project and configuration" \
    "$(cli check --to elsewhere)"
assert_eq "continue without --to says the MCP tools hand off on this computer" \
    "t3: continue starts a thread on another computer: --to <computer> is required. On this computer, the agent hands off with its t3-code MCP tools." \
    "$(cli continue --title x --prompt-file x)"
assert_eq "continue needs the next title" \
    "t3: --title <title> is required: the next title \`t3.mjs title\` printed" \
    "$(cli continue --to elsewhere --from x --prompt-file x)"
assert_eq "title needs the current title" \
    "t3: --current <title> is required" \
    "$(cli title)"
assert_eq "--key without --description is refused" \
    "t3: --key and --description go together" \
    "$(cli title --current x --key KTLO-1)"
assert_eq "title prints the rename and the next title as JSON" \
    '{"rename":"RIG - [dotfiles#94] Handoff over MCP","next":"RIG - [dotfiles#94] Handoff over MCP 1"}' \
    "$(node "$module" title --current 'Move the handoff' --key 'dotfiles#94' --description 'Handoff over MCP')"
assert_eq "title prints no rename for a standard title" \
    '{"next":"RIG - [dotfiles#94] Handoff over MCP 2"}' \
    "$(node "$module" title --current 'RIG - [dotfiles#94] Handoff over MCP 1')"

# from <json>: prints the project title --from reads out of a file holding the json, or the error.
from() {
    printf '%s' "$1" > "$work/from.json"
    call "t3.readFrom(String.raw\`$(cd "$work" && (pwd -W 2>/dev/null || pwd))/from.json\`).project.title"
}

assert_eq "--from reads the project and configuration the MCP tools gave" \
    "dotfiles-private" \
    "$(from '{"project":{"title":"dotfiles-private","workspaceRoot":"/w/here"},"configuration":{"modelSelection":{"instanceId":"claudeAgent","model":"m"},"runtimeMode":"full-access","interactionMode":"default"}}')"
assert_eq "--from names every field it lacks" \
    "error: --from $(cd "$work" && (pwd -W 2>/dev/null || pwd))/from.json has no project.workspaceRoot, configuration.runtimeMode, configuration.interactionMode" \
    "$(from '{"project":{"title":"dotfiles-private"},"configuration":{"modelSelection":{"model":"m"}}}')"
# Node words the parse error itself differently from version to version, so only what t3.mjs says is compared.
assert_eq "--from that is not JSON says so" \
    "error: --from $(cd "$work" && (pwd -W 2>/dev/null || pwd))/from.json cannot be read as JSON" \
    "$(from 'not json' | sed 's/ as JSON: .*/ as JSON/')"

assert_eq "--ttl takes a count and a unit, which reach a shell on Windows" \
    "t3: --ttl must be a count and a unit such as 365d, not 1d & calc" \
    "$(cli token --ttl '1d & calc')"
assert_eq "--ttl of nothing is refused" \
    "t3: --ttl must be a count and a unit such as 365d, not 0d" \
    "$(cli token --ttl 0d)"
assert_eq "--ttl takes a unit in words, as T3 does" \
    "2 weeks" \
    "$(call "t3.parseArgs(['token', '--ttl', '2 weeks']).flags.ttl")"
assert_summary "t3-handoff"
