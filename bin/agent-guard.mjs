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
//     and `Invoke-Expression`, encoded ones included, and those in script blocks, groups and
//     double-quoted `$(…)`, are judged as well.
//   - asks before `elevate enable`, which turns a disabled runner back on.
//
// Only commands are judged, never what they carry: heredoc bodies and quoted strings are taken
// out first, so a commit message or a PR body that mentions `sed -i` passes. The elevation rules
// read a quoted string, or a PowerShell here-string, as one word, so a quoted path or task name
// still counts as an argument and a message never reads as a command.
//
// It is a soft control. It sees only the commands Claude Code's Bash and PowerShell tools are
// given: not the Write and Edit tools, not what a script they run does, nor a path or a host name
// built up at run time. The runner's own approval is the gate; this steers an agent to it.
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
// A name or address list the OS will not give is left out rather than thrown: the hook blocks
// every shell call when it fails, and the rest of the rules do not need either.
const orEmpty = (read) => {
    try {
        return read();
    } catch {
        return [];
    }
};
function thisMachine() {
    const names = [process.env.COMPUTERNAME, ...orEmpty(() => [hostname()])].filter(Boolean).map((n) => n.toLowerCase());
    const addresses = orEmpty(() => Object.values(networkInterfaces()).flat())
        .map((a) => a.address.toLowerCase().replace(/%.*$/, ''));
    return { platform: process.platform, names, addresses };
}

// shellWords(text, tool): the commands in text, as pipelines of argument lists. A quoted string,
// and in PowerShell a here-string, is one word with its quotes taken off; a `$(…)` inside double
// quotes runs, so its commands are added at the end. Line continuations are joined first: a
// backtick in PowerShell, a backslash elsewhere. Script blocks, groups and a lone `&`
// (PowerShell's call operator, or a background job) end a pipeline, and what can stand before a
// command word (an assignment, `env`, `command`, `exec`, `nohup`, `time`, `timeout`, `nice`, a
// dot-source) is dropped. PowerShell takes typographic dashes and quotes as plain ones.
const placeholder = /\u0001(\d+)\u0002/g;
const powerShellQuoted = /@'[ \t]*\r?\n[\s\S]*?\r?\n'@|@"[ \t]*\r?\n[\s\S]*?\r?\n"@|'(?:[^']|'')*'|"(?:[^"`]|`[\s\S]|"")*"/g;
const prefixCommands = new Set(['env', 'command', 'exec', 'nohup', 'time', 'timeout', 'nice', 'builtin']);
function shellWords(text, tool) {
    const powerShell = tool === 'PowerShell';
    const source = powerShell
        ? text.replace(/[–—―]/g, '-').replace(/[‘’‚‛]/g, '\'')
            .replace(/[“”„]/g, '"').replace(/`\r?\n/g, ' ')
        : text.replace(/\\\r?\n/g, ' ');
    const strings = [];
    const substituted = [];
    const hidden = source
        .replace(powerShell ? powerShellQuoted : quoted, (q) => {
            if (/^@?"/.test(q)) substituted.push(...[...q.matchAll(/\$\(([^()]*)\)/g)].map((m) => m[1]));
            return `\u0001${strings.push(q.startsWith('@') ? q.slice(2, -2) : q.slice(1, -1)) - 1}\u0002`;
        })
        .replace(/\$\{[^{}\s]*\}/g, (v) => `\u0001${strings.push(v) - 1}\u0002`);
    const words = (c) => withoutPrefixes(c.split(/\s+/).filter(Boolean).map((w) => w.replace(placeholder, (_, i) => strings[i])));
    return [
        ...pipelines(hidden.replace(/[{})]/g, '\n')).flatMap((p) => p.split('&'))
            .map((p) => commands(p).map(words).filter((argv) => argv.length)).filter((p) => p.length),
        ...substituted.flatMap((s) => shellWords(s, tool)),
    ];
}
function withoutPrefixes(argv) {
    let words = argv;
    for (;;) {
        const [first = '', second = ''] = words;
        if (first === 'command' && /^-[vV]$/.test(second)) return [];
        if (first === '.') words = words.slice(1);
        else if (/^\$[\w:]+$/.test(first) && second === '=') words = words.slice(2);
        else if (/^\$[\w:]+=/.test(first)) words = [first.replace(/^\$[\w:]+=/, ''), ...words.slice(1)].filter(Boolean);
        else if (/^[A-Za-z_]\w*=/.test(first)) words = words.slice(1);
        else if (prefixCommands.has(first)) {
            words = words.slice(1);
            while (words[0]?.startsWith('-')) words = words.slice(1);
            if (first === 'timeout' && /^\d/.test(words[0] ?? '')) words = words.slice(1);
        } else return words;
    }
}

// commandName(word): the command a word runs, lower case, without its folder or extension.
const commandName = (word = '') => word.split(/[\\/]/).pop().toLowerCase().replace(/\.(exe|ps1|cmd|bat|com)$/, '');
// abbreviates(word, name): word is `-name`, or `/name`, or a prefix of it, as powershell.exe takes.
const abbreviates = (word, name) => /^[-/]./.test(word) && name.startsWith(word.slice(1).toLowerCase());

// handedCode(argv): the code a shell is handed to run, as texts to read as commands in tool's
// syntax and argvs already split, or null when argv hands none. powershell.exe runs a bare first
// word as -Command; these are the options that take a value before it.
const valuedPowerShellOption = /^[-/](ex\w*|ep|w\w*|v\w*|psc\w*|inp\w*|if|o\w*|con\w*|wd|cus\w*|set\w*)$/i;
const code = (tool, texts, argvs = []) => ({ tool, texts, argvs });
function handedCode(argv) {
    const name = commandName(argv[0]);
    const rest = argv.slice(1);
    if (name === 'powershell' || name === 'pwsh') {
        for (let i = 0; i < rest.length; i++) {
            const word = rest[i];
            if (abbreviates(word, 'command')) return code('PowerShell', [rest.slice(i + 1).join(' ')]);
            if (abbreviates(word, 'file')) return code('PowerShell', [], [rest.slice(i + 1)]);
            if (abbreviates(word, 'encodedcommand') || /^[-/]ec$/i.test(word)) {
                return code('PowerShell', [Buffer.from(rest[i + 1] ?? '', 'base64').toString('utf16le')]);
            }
            if (!/^[-/]/.test(word)) return code('PowerShell', [rest.slice(i).join(' ')]);
            if (valuedPowerShellOption.test(word)) i += 1;
        }
        return null;
    }
    if (/^(bash|sh|zsh|dash|ksh)$/.test(name)) {
        const i = rest.findIndex((w) => /^-[a-zA-Z]*c[a-zA-Z]*$/.test(w));
        return i < 0 ? null : code('Bash', [rest[i + 1] ?? '']);
    }
    if (name === 'cmd') {
        const i = rest.findIndex((w) => /^\/{1,2}[ck]$/i.test(w));
        return i < 0 ? null : code('Bash', [rest.slice(i + 1).join(' ')]);
    }
    if (name === 'invoke-expression' || name === 'iex') {
        return code('PowerShell', [rest.filter((w) => !abbreviates(w, 'command')).join(' ')]);
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

// sshToSelf(argv, machine): ssh, scp or sftp, on Windows, whose destination, remote or jump host
// (-J, -o ProxyJump, -o HostName) is this machine: a loopback name or address, one of its own
// addresses, its own name or a name under it. An admin signing in over ssh gets a full token,
// which no UAC prompt stands in front of. A Host alias in ~/.ssh/config is not resolved.
const sshValued = { ssh: 'BbcDEeFIiJLlmOoPpQRSWw', scp: 'cDFiJloPSX', sftp: 'BbcDFiJloPRSs' };
const loopback = /^(localhost|.+\.localhost|127(\.\d+){1,3}|0\.0\.0\.0|::1|(0{1,4}:){7}0{0,3}1|::ffff:127(\.\d+){3})$/;
function hostName(destination) {
    let host = destination.replace(/^[a-z]+:\/\//i, '').replace(/\/.*$/, '');
    host = host.slice(host.lastIndexOf('@') + 1);
    if (host.startsWith('[')) host = host.slice(1).replace(/\].*$/, '');
    else if (host.split(':').length === 2) host = host.split(':')[0];
    return host.toLowerCase().replace(/\.$/, '');
}
function sshHosts(argv) {
    const command = commandName(argv[0]);
    const valued = sshValued[command];
    if (!valued) return [];
    const hosts = [];
    for (let i = 1; i < argv.length; i++) {
        const word = argv[i];
        if (word.startsWith('-') && word !== '-') {
            for (let j = 1; j < word.length; j++) {
                if (!valued.includes(word[j])) continue;
                const value = word.slice(j + 1) || argv[++i] || '';
                const option = /^(?:proxyjump|hostname)\s*=?\s*(.+)$/i.exec(value);
                if (word[j] === 'J') hosts.push(...value.split(','));
                else if (word[j] === 'o' && option) hosts.push(...option[1].split(','));
                break;
            }
        } else if (command === 'scp') {
            // A remote is [user@]host:path; a single letter before the colon is a Windows drive.
            const remote = /^(?:scp:\/\/)?(?:[^@/\\]*@)?(\[[^\]]*\]|[^:/\\]{2,}):/i.exec(word);
            if (remote) hosts.push(remote[1]);
        } else {
            hosts.push(command === 'sftp' && !/^\w+:\/\//.test(word) ? word.replace(/^(\[[^\]]*\]|[^:]*):.*$/, '$1') : word);
            break;
        }
    }
    return hosts.map(hostName);
}
function sshToSelf(argv, machine) {
    return machine.platform === 'win32' && sshHosts(argv).some((host) => loopback.test(host)
        || machine.addresses.includes(host) || machine.names.some((name) => host === name || host.startsWith(`${name}.`)));
}

// writesRunnerRoot(argv): a command given a path in C:\ProgramData\ElevatedRuns, in any of the
// ways the shells spell it, other than elevate and other than one that only reads: a reader, a
// copy whose destination is elsewhere, or icacls without a switch that changes access. An
// interpreter counts when its code or arguments name the root anywhere. Moving into the root
// with cd counts, since what follows would write there by a relative path.
// ProgramData is also reached through its short name and the `All Users` and `Application Data`
// junctions, and a path may carry the `\\?\` or `\\.\` prefix.
const programData = String.raw`(?:programdata(?:[\\/]+application data)?|progra~\d|users[\\/]+all users)`;
const rootPattern = String.raw`(?:(?:\\\\[?.]\\)?[a-z]:[\\/]+${programData}`
    + String.raw`|\/(?:mnt\/|cygdrive\/)?[a-z]\/+${programData}|%(?:programdata|allusersprofile)%`
    + String.raw`|\$(?:env:|\{env:|\{|\(\$env:)?(?:programdata|allusersprofile)[})]?)[\\/]+(?:elevatedruns|elevat~\d)(?![\w.-])`;
const runnerRoot = new RegExp(`^${rootPattern}`, 'i');
const runnerRootAnywhere = new RegExp(`(?<!\\w)${rootPattern}`, 'i');
const namesRunnerRoot = (word) => runnerRoot.test(word.replace(/^(?:-{1,2}[\w-]+[:=]|\w+=)/, ''));
const readsOnly = new Set(['get-content', 'gc', 'cat', 'type', 'more', 'less', 'head', 'tail', 'ls', 'dir',
    'gci', 'get-childitem', 'get-item', 'gi', 'get-itemproperty', 'gp', 'get-itempropertyvalue', 'gpv',
    'test-path', 'resolve-path', 'rvpa', 'get-acl', 'select-string', 'sls', 'grep', 'rg', 'findstr', 'wc',
    'stat', 'get-filehash', 'md5sum', 'sha1sum', 'sha256sum', 'jq', 'diff', 'cmp', 'import-csv', 'ipcsv',
    'convertfrom-json', 'echo', 'write-output', 'write-host', 'split-path', 'join-path', 'tree', 'du', 'explorer']);
const copiers = new Set(['copy-item', 'cpi', 'copy', 'cp', 'xcopy']);
const interpreters = /^(node|python3?|py|perl|ruby|deno)$/;
const changesAccess = /^\/(grant|deny|remove|setowner|reset|inheritance|restore|setintegritylevel|substitute)/i;
function copyDestination(argv) {
    for (let i = 1; i < argv.length; i++) {
        const option = /^(?:-des\w*|-t|--target-directory)(?:[:=](.*))?$/i.exec(argv[i]);
        if (option) return option[1] ?? argv[i + 1] ?? '';
    }
    return argv.slice(1).filter((w) => !w.startsWith('-') && !/^\/[a-z?]{1,2}$/i.test(w)).pop() ?? '';
}
const redirectsIntoRoot = (argv) => argv.some((word, i) => word.includes('>')
    && namesRunnerRoot(word.slice(word.lastIndexOf('>') + 1) || argv[i + 1] || ''));
function writesRunnerRoot(argv) {
    if (redirectsIntoRoot(argv)) return true;
    const name = commandName(argv[0]);
    if (interpreters.test(name)) return argv.some((w) => runnerRootAnywhere.test(w));
    if (copiers.has(name)) return namesRunnerRoot(copyDestination(argv));
    if (name === 'elevate' || readsOnly.has(name) || (name === 'icacls' && !argv.some((w) => changesAccess.test(w)))) return false;
    return argv.some(namesRunnerRoot);
}

// pipesOutOfRoot(argvs): a command naming the root, followed in the same call by one that acts on
// the paths it is handed (`| Remove-Item`, `| ForEach-Object { Remove-Item $_ }`, `| xargs rm`).
const pathTakers = new Set(['remove-item', 'rm', 'ri', 'del', 'erase', 'rd', 'rmdir', 'move-item', 'mv', 'mi',
    'move', 'rename-item', 'ren', 'rni', 'clear-item', 'cli', 'set-item', 'si', 'set-itemproperty', 'sp',
    'clear-content', 'clc', 'set-acl']);
const takesPipedPath = (argv) => commandName(argv[0]) === 'xargs' || (pathTakers.has(commandName(argv[0]))
    && argv.slice(1).filter((w) => !w.startsWith('-')).every((w) => /^\$(_|psitem)\b/i.test(w)));
function pipesOutOfRoot(argvs) {
    const first = argvs.findIndex((argv) => argv.some(namesRunnerRoot));
    return first >= 0 && argvs.slice(first + 1).some(takesPipedPath);
}

// changesRunnerTask(argvs): a call that runs, changes, replaces or removes a scheduled task and
// names the `Elevated runs` task anywhere in it: by name, path or wildcard to a task command, or
// as the value of an assignment, so a task piped in or kept in a variable in the same call counts.
// Reading it, and ending a run, are allowed.
const taskCmdlet = /^(get|start|set|register|unregister|enable|disable)-scheduledtask$/;
const changesTask = (argv) => {
    const name = commandName(argv[0]);
    if (name === 'schtasks') return argv.some((w) => /^(\/{1,2}|-)(run|change|delete|create)$/i.test(w));
    return taskCmdlet.test(name) && name !== 'get-scheduledtask';
};
const wildcard = (pattern) => new RegExp(`^${pattern.replace(/[.+^${}()|[\]]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`);
const namesRunnerTask = (argv) => {
    const name = commandName(argv[0]);
    if (argv.length === 1 && argv[0].split('\\').pop().toLowerCase() === 'elevated runs') return true;
    return (name === 'schtasks' || taskCmdlet.test(name)) && argv.slice(1).some((word) => {
        const task = word.replace(/^-[\w-]+:/, '').split('\\').pop().toLowerCase();
        return /[*?]/.test(task) ? wildcard(task).test('elevated runs') : task === 'elevated runs';
    });
};
const changesRunnerTask = (argvs) => argvs.some(changesTask) && argvs.some(namesRunnerTask);

// enablesRunner(argv): elevate, with enable among its words.
const enablesRunner = (argv) => commandName(argv[0]) === 'elevate'
    && argv.slice(1).some((w) => w.toLowerCase() === 'enable');

// elevation(pipes, machine): 'deny', 'ask' or null for these pipelines and the code their commands
// hand to another shell, which is judged in their place, the wrapper's own redirect included.
function elevation(pipes, machine, depth = 0) {
    const argvs = pipes.flat();
    const answers = argvs.map((argv) => {
        const handed = depth < 4 && handedCode(argv);
        if (handed) {
            if (redirectsIntoRoot(argv)) return 'deny';
            return elevation([...handed.texts.flatMap((t) => shellWords(t, handed.tool)), ...handed.argvs.map((a) => [a])],
                machine, depth + 1);
        }
        if (startsElevated(argv) || runsAsAdmin(argv, machine) || sshToSelf(argv, machine) || writesRunnerRoot(argv)) return 'deny';
        return enablesRunner(argv) ? 'ask' : null;
    });
    if (changesRunnerTask(argvs) || pipesOutOfRoot(argvs) || answers.includes('deny')) return 'deny';
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
    const elevated = elevation(shellWords(bodiless, tool), machine);
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
