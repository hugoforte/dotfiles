#!/usr/bin/env node

// agent-guard: a Claude Code PreToolUse hook for the shell tools.
//
// Reads the hook's JSON on stdin and answers on stdout, or prints nothing to let the call through:
//
//   - refuses a Bash command that writes a file or a script through a heredoc, or edits a file in
//     place with `perl -i` or `sed -i`. Quotes and backslashes in the body break on the way
//     through Git Bash, and a broken `\n` has left source files unparseable. Edit and Write do
//     the same job without the shell in between.
//   - asks before a pull request is merged with `gh pr merge`, `gh stack merge` or `gh api`, from
//     either shell. Merging is the human's call.
//   - refuses an elevated step taken any way but through the elevated-runs runner's client,
//     `elevate`, from either shell: `Start-Process -Verb RunAs` (and `saps`, `start`), `runas`,
//     `gsudo`, `sudo.exe`, and `sudo` on Windows; running or changing the `Elevated runs`
//     scheduled task; `ssh` to this machine's own names or addresses on Windows, where an admin
//     signing in over ssh gets a full token without a UAC prompt; and writes into
//     `C:\ProgramData\ElevatedRuns`. Commands handed to `powershell`, `pwsh`, `cmd /c`, `bash -c`
//     and `Invoke-Expression`, encoded ones included, are judged as well.
//   - asks before `elevate enable`, which turns a disabled runner back on.
//
// Only commands are judged, never what they carry: heredoc bodies and quoted strings are taken
// out first, so a commit message or a PR body that mentions `sed -i` passes. The elevation rules
// read a quoted string as one word, so a quoted path or task name still counts as an argument.
//
// It is a soft control. It sees only the commands Claude Code's Bash and PowerShell tools are
// given, not what a script they run does, nor a path or a host name built up at run time. The
// runner's own approval is the gate; this steers an agent to it.
//
// ai/claude/settings.json registers it as `node agent-guard.mjs` in exec form, blocking the call
// if it cannot run, and ai/install.sh writes this checkout's absolute path to it into each live
// settings.json, so it is found whatever PATH the agent was started with. `node` still is not.

import { readFileSync, realpathSync } from 'node:fs';
import { hostname, networkInterfaces } from 'node:os';
import { fileURLToPath } from 'node:url';

const heredocOpener = /(?<!<)<<(?!<)-?\s*(['"]?)([\w.-]+)\1/g;
const interpreter = /^(\S*\/)?(python3?|py|node|perl|ruby|bash|sh)\b/;
const fileRedirect = /(^|\s)\d?>{1,2}\s*(?!&|\/dev\/null\b)\S/;
// perl's -i counts only among perl's own switches, which run until the script or the first word
// that is not one; an -e or -E takes the next word as its code, and switches may follow it.
const inPlaceEdit = /^(sed\b.*\s(-[a-zA-Z]*i|--in-place)|perl(\s+(-[a-zA-Z]*[eE]\s+\S+|-\S+))*?\s+-[a-zA-Z]*i)/;
const ghMerge = /^gh\s+(pr|stack)\s+merge\b/;
const ghApiMerge = /^gh\s+api\b(?=.*\/pulls\/[^/\s]+\/merge\b)(?=.*(-X\s*|--method[\s=]+)PUT\b)/;
const ghGraphqlMerge = /^gh\s+api\s+graphql\b.*\b(mergePullRequest|enablePullRequestAutoMerge)\b/;

const writeThroughShell = 'Write files and scripts with the Write tool and edit them with Edit, then run them. '
    + 'A heredoc or an in-place perl/sed edit loses quotes and backslashes on the way through Git Bash.';
const mergeIsHuman = 'Merging a pull request is the human\'s call. Go ahead only if they named this PR for merging in this session.';

const quoted = /'[^']*'|"(?:[^"\\]|\\.)*"/g;

// withoutQuotes(text): each quoted string blanked, except a single word, which is unwrapped so a
// quoted command word (`gh "pr" merge`) is still read as one.
const withoutQuotes = (text) => text.replace(quoted, (q) => (/^.[\w.-]*.$/.test(q) ? q.slice(1, -1) : '""'));

// withoutHeredocBodies(command): the command with every heredoc's body and closing marker removed.
// Openers are looked for outside quoted strings, but a quoted marker straight after `<<` counts.
function withoutHeredocBodies(command) {
    const kept = [];
    let markers = [];
    for (const line of command.split('\n')) {
        if (markers.length) {
            if (line.trim() === markers[0]) markers.shift();
            continue;
        }
        kept.push(line);
        const unquoted = line.replace(/(<<-?\s*)?('[^']*'|"(?:[^"\\]|\\.)*")/g, (m, opener) => (opener ? m : '""'));
        markers = [...unquoted.matchAll(heredocOpener)].map((m) => m[2]);
    }
    return kept.join('\n');
}

// pipelines(text): each pipeline, trimmed. commands(pipeline): its commands, trimmed, so a pattern
// anchored with ^ is in command position.
const pipelines = (text) => text.split(/\n|;|&&|\|\||\$\(|\(|`/).map((s) => s.trim()).filter(Boolean);
const commands = (pipeline) => pipeline.split('|').map((s) => s.trim()).filter(Boolean);

// writesThroughShell(pipeline): a heredoc that ends in a file or an interpreter, or an in-place edit.
function writesThroughShell(pipeline) {
    const parts = commands(pipeline);
    if (/(?<!<)<<(?!<)/.test(pipeline)
        && (fileRedirect.test(pipeline) || parts.some((c) => interpreter.test(c) || /^tee\b/.test(c)))) {
        return true;
    }
    return parts.some((c) => inPlaceEdit.test(c));
}

const elevatedThroughRunner = 'Elevated steps go through the hf-elevate skill (`elevate request`).';
const enableIsHuman = '`elevate enable` turns a disabled elevated-runs runner back on, which is the human\'s call. '
    + 'Go ahead only if they asked for it in this session.';

// thisMachine(): what the sudo and self-ssh rules need to know about the machine the hook runs on.
function thisMachine() {
    const names = [hostname(), process.env.COMPUTERNAME].filter(Boolean).map((n) => n.toLowerCase());
    const addresses = Object.values(networkInterfaces()).flat()
        .map((a) => a.address.toLowerCase().replace(/%.*$/, ''));
    return { platform: process.platform, names, addresses };
}

// shellWords(text): each command in text as its words, a quoted string being one word with its
// quotes taken off. Line continuations are joined first, a lone `&` (PowerShell's call operator,
// or a background job) ends a command as `|` does, and what can stand before a command word
// (an assignment, `env`, `command`, `exec`, `nohup`, `time`, `nice`, a dot-source) is dropped.
const placeholder = /\u0001(\d+)\u0002/g;
const prefixCommands = new Set(['env', 'command', 'exec', 'nohup', 'time', 'nice', 'builtin']);
function shellWords(text) {
    const strings = [];
    const hidden = text.replace(/[`\\]\r?\n/g, ' ')
        .replace(quoted, (q) => `\u0001${strings.push(q.slice(1, -1)) - 1}\u0002`);
    return pipelines(hidden).flatMap(commands).flatMap((c) => c.split('&'))
        .map((c) => withoutPrefixes(c.split(/\s+/).filter(Boolean)
            .map((w) => w.replace(placeholder, (_, i) => strings[i]))))
        .filter((argv) => argv.length);
}
function withoutPrefixes(argv) {
    let words = argv;
    for (;;) {
        const [first = '', second = ''] = words;
        if (first === 'command' && /^-[vV]$/.test(second)) return [];
        if (first === '.') words = words.slice(1);
        else if (/^\$[\w:]+$/.test(first) && second === '=') words = words.slice(2);
        else if (/^[A-Za-z_]\w*=/.test(first)) words = words.slice(1);
        else if (prefixCommands.has(first)) {
            words = words.slice(1);
            while (words[0]?.startsWith('-')) words = words.slice(1);
        } else return words;
    }
}

// commandName(word): the command a word runs, lower case, without its folder or extension.
const commandName = (word = '') => word.split(/[\\/]/).pop().toLowerCase().replace(/\.(exe|ps1|cmd|bat|com)$/, '');
// abbreviates(word, name): word is `-name`, or `/name`, or a prefix of it, as powershell.exe takes.
const abbreviates = (word, name) => /^[-/]./.test(word) && name.startsWith(word.slice(1).toLowerCase());

// handedCode(argv): the code a shell is handed to run, as { texts } to read as commands or
// { argvs } already split, or null when argv hands none. powershell.exe runs a bare first word as
// -Command; these are the options that take a value before it.
const valuedPowerShellOption = /^[-/](ex\w*|ep|w\w*|v\w*|psc\w*|inp\w*|if|o\w*|con\w*|wd|cus\w*|set\w*)$/i;
function handedCode(argv) {
    const name = commandName(argv[0]);
    const rest = argv.slice(1);
    if (name === 'powershell' || name === 'pwsh') {
        for (let i = 0; i < rest.length; i++) {
            const word = rest[i];
            if (abbreviates(word, 'command')) return { texts: [rest.slice(i + 1).join(' ')] };
            if (abbreviates(word, 'file')) return { argvs: [rest.slice(i + 1)] };
            if (abbreviates(word, 'encodedcommand') || /^[-/]ec$/i.test(word)) {
                return { texts: [Buffer.from(rest[i + 1] ?? '', 'base64').toString('utf16le')] };
            }
            if (!/^[-/]/.test(word)) return { texts: [rest.slice(i).join(' ')] };
            if (valuedPowerShellOption.test(word)) i += 1;
        }
        return null;
    }
    if (/^(bash|sh|zsh|dash|ksh)$/.test(name)) {
        const i = rest.findIndex((w) => /^-[a-zA-Z]*c[a-zA-Z]*$/.test(w));
        return i < 0 ? null : { texts: [rest[i + 1] ?? ''] };
    }
    if (name === 'cmd') {
        const i = rest.findIndex((w) => /^\/{1,2}[ck]$/i.test(w));
        return i < 0 ? null : { texts: [rest.slice(i + 1).join(' ')] };
    }
    if (name === 'invoke-expression' || name === 'iex') {
        return { texts: [rest.filter((w) => !abbreviates(w, 'command')).join(' ')] };
    }
    return null;
}

// startsElevated(argv): Start-Process, or its aliases, with -Verb RunAs or RunAsUser (another
// user, such as an admin, given a credential prompt).
function startsElevated(argv) {
    if (!['start-process', 'saps', 'start'].includes(commandName(argv[0]))) return false;
    return argv.some((word, i) => {
        const verb = /^-verb(?::(.*))?$/i.exec(word);
        return verb && /^runas(user)?$/i.test(verb[1] || argv[i + 1] || '');
    });
}

// runsAsAdmin(argv, machine): runas, gsudo, Windows' sudo.exe, or sudo on Windows. sudo on macOS
// and Linux is the ordinary way to an admin step, and there is no runner there to send it to.
function runsAsAdmin(argv, machine) {
    const name = commandName(argv[0]);
    return name === 'runas' || name === 'gsudo' || /(^|[\\/])sudo\.exe$/i.test(argv[0])
        || (name === 'sudo' && machine.platform === 'win32');
}

// sshToSelf(argv, machine): ssh, on Windows, whose destination or jump host is this machine: a
// loopback name or address, one of its own addresses, its own name or a name under it. An admin
// signing in over ssh gets a full token, which no UAC prompt stands in front of. A Host alias in
// ~/.ssh/config is not resolved.
const sshValued = 'BbcDEeFIiJLlmOoPpQRSWw';
const loopback = /^(localhost|.+\.localhost|127(\.\d+){1,3}|0\.0\.0\.0|::1|(0{1,4}:){7}0{0,3}1|::ffff:127(\.\d+){3})$/;
function sshHosts(argv) {
    const hosts = [];
    for (let i = 1; i < argv.length; i++) {
        const word = argv[i];
        if (!word.startsWith('-') || word === '-') {
            hosts.push(word);
            break;
        }
        for (let j = 1; j < word.length; j++) {
            if (!sshValued.includes(word[j])) continue;
            const value = word.slice(j + 1) || argv[++i] || '';
            if (word[j] === 'J') hosts.push(...value.split(','));
            break;
        }
    }
    return hosts.map((destination) => {
        let host = destination.replace(/^ssh:\/\//i, '').replace(/\/.*$/, '');
        host = host.slice(host.lastIndexOf('@') + 1);
        if (host.startsWith('[')) host = host.slice(1).replace(/\].*$/, '');
        else if (host.split(':').length === 2) host = host.split(':')[0];
        return host.toLowerCase().replace(/\.$/, '');
    });
}
function sshToSelf(argv, machine) {
    return machine.platform === 'win32' && commandName(argv[0]) === 'ssh' && sshHosts(argv).some((host) => loopback.test(host)
        || machine.addresses.includes(host) || machine.names.some((name) => host === name || host.startsWith(`${name}.`)));
}

// writesRunnerRoot(argv): a command other than elevate, and other than one that only reads, given
// a path in C:\ProgramData\ElevatedRuns, in any of the ways the shells spell it, or a redirect
// into it. Moving into it with cd counts, since what follows would write there by a relative path.
const runnerRoot = new RegExp(String.raw`^(?:(?:\\\\\?\\)?[a-z]:[\\/]+(?:programdata|progra~3)`
    + String.raw`|\/(?:mnt\/|cygdrive\/)?[a-z]\/+(?:programdata|progra~3)|%(?:programdata|allusersprofile)%`
    + String.raw`|\$(?:env:|\{env:|\{|\(\$env:)?(?:programdata|allusersprofile)[})]?)[\\/]+elevatedruns(?![\w.-])`, 'i');
const namesRunnerRoot = (word) => runnerRoot.test(word.replace(/^(?:-{1,2}[\w-]+[:=]|\w+=)/, ''));
const readsOnly = new Set(['get-content', 'gc', 'cat', 'type', 'more', 'less', 'head', 'tail', 'ls', 'dir',
    'gci', 'get-childitem', 'get-item', 'gi', 'get-itemproperty', 'gp', 'test-path', 'resolve-path', 'rvpa',
    'get-acl', 'select-string', 'sls', 'grep', 'rg', 'findstr', 'wc', 'stat', 'get-filehash', 'echo',
    'write-output', 'write-host', 'split-path', 'join-path', 'tree', 'du']);
function writesRunnerRoot(argv) {
    if (argv.some((word, i) => word.includes('>')
        && namesRunnerRoot(word.slice(word.lastIndexOf('>') + 1) || argv[i + 1] || ''))) return true;
    const name = commandName(argv[0]);
    return name !== 'elevate' && !readsOnly.has(name) && argv.some(namesRunnerRoot);
}

// changesRunnerTask(argvs): a call that runs, changes, replaces or removes a scheduled task and
// names the `Elevated runs` task, by name, path or wildcard, anywhere in it, so a task piped in
// or kept in a variable counts. Reading it, and ending a run, are allowed.
const taskCmdlet = /^(get|start|set|register|unregister|enable|disable)-scheduledtask$/;
const changesTask = (argv) => {
    const name = commandName(argv[0]);
    if (name === 'schtasks') return argv.some((w) => /^(\/{1,2}|-)(run|change|delete|create)$/i.test(w));
    return taskCmdlet.test(name) && name !== 'get-scheduledtask';
};
const wildcard = (pattern) => new RegExp(`^${pattern.replace(/[.+^${}()|[\]]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`);
const namesRunnerTask = (argv) => {
    const name = commandName(argv[0]);
    return (name === 'schtasks' || taskCmdlet.test(name)) && argv.slice(1).some((word) => {
        const task = word.replace(/^-[\w-]+:/, '').split('\\').pop().toLowerCase();
        return /[*?]/.test(task) ? wildcard(task).test('elevated runs') : task === 'elevated runs';
    });
};
const changesRunnerTask = (argvs) => argvs.some(changesTask) && argvs.some(namesRunnerTask);

// enablesRunner(argv): elevate enable.
const enablesRunner = (argv) => commandName(argv[0]) === 'elevate'
    && argv.slice(1).find((w) => !w.startsWith('-'))?.toLowerCase() === 'enable';

// elevation(argvs, machine): 'deny', 'ask' or null for these commands and the code they hand to
// another shell, which is judged in their place.
function elevation(argvs, machine, depth = 0) {
    const answers = argvs.map((argv) => {
        const code = depth < 4 && handedCode(argv);
        if (code) return elevation([...(code.texts ?? []).flatMap(shellWords), ...(code.argvs ?? [])], machine, depth + 1);
        if (startsElevated(argv) || runsAsAdmin(argv, machine) || sshToSelf(argv, machine) || writesRunnerRoot(argv)) return 'deny';
        return enablesRunner(argv) ? 'ask' : null;
    });
    if (changesRunnerTask(argvs) || answers.includes('deny')) return 'deny';
    return answers.includes('ask') ? 'ask' : null;
}

// verdict(tool, command, machine): { decision: 'deny' | 'ask', reason } or null to let the call
// through. A refusal wins over a question, so approving a merge cannot carry a refused write with
// it. machine is this one unless a test says otherwise.
export function verdict(tool, command, machine = thisMachine()) {
    if (typeof command !== 'string') return null;
    const bodiless = withoutHeredocBodies(command);
    const stripped = pipelines(withoutQuotes(bodiless));
    if (tool === 'Bash' && stripped.some(writesThroughShell)) return { decision: 'deny', reason: writeThroughShell };
    const elevated = elevation(shellWords(bodiless), machine);
    if (elevated === 'deny') return { decision: 'deny', reason: elevatedThroughRunner };
    // gh api's path and a graphql query are quoted strings, so those are read with quotes in.
    const raw = pipelines(bodiless).flatMap(commands);
    const merges = stripped.flatMap(commands).some((c) => ghMerge.test(c))
        || raw.some((c) => ghApiMerge.test(c) || ghGraphqlMerge.test(c));
    const asks = [merges && mergeIsHuman, elevated === 'ask' && enableIsHuman].filter(Boolean);
    return asks.length ? { decision: 'ask', reason: asks.join(' ') } : null;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    // Defensive: a hand-run test from Windows PowerShell 5.1 pipes a byte-order mark first.
    const input = JSON.parse(readFileSync(0, 'utf8').replace(/^﻿/, ''));
    const answer = verdict(input.tool_name, input.tool_input?.command);
    if (answer) {
        process.stdout.write(JSON.stringify({
            hookSpecificOutput: {
                hookEventName: 'PreToolUse',
                permissionDecision: answer.decision,
                permissionDecisionReason: answer.reason,
            },
        }));
    }
}
