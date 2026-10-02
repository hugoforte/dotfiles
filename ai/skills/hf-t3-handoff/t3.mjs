#!/usr/bin/env node
// Continues the current T3 Code thread in a new one: creates the next thread in
// the same project, branch and model, sends it the prompt, waits for its turn to
// start, then archives the current thread (renamed first when it was not yet
// standard; see handoffTitles).
//
//   node t3.mjs check
//   node t3.mjs continue --prompt-file <path> [--key <key> --description <text>]
//                        [--thread <id>] [--dry-run]
//
// `check` lists everything the handoff needs and how to fix what is missing.
//
// It drives the local T3 Code server's HTTP API, which is what T3's own web
// client uses. That API is internal to an alpha app, so every call checks its
// answer and stops with the response it got rather than guessing.

import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const T3_HOME = process.env.T3CODE_HOME ?? join(homedir(), '.t3');
const T3_EXE = process.env.T3_EXE ?? join(process.env.LOCALAPPDATA ?? '', 'Programs', 't3code', 'T3 Code (Alpha).exe');
const RIG_HANDOFF_SKILL = join(homedir(), '.claude', 'skills', 'rig-handoff', 'SKILL.md');
const TURN_START_TIMEOUT_MS = 60_000;
const USAGE = 'usage: t3.mjs check\n       t3.mjs continue --prompt-file <path> [--key <key> --description <text>] [--thread <id>] [--dry-run]';

const STANDARD_TITLE = /^RIG - \[([^\]]+)\] (.*?\S)(?: (\d+))?$/;

/**
 * The titles a handoff gives the current thread and the next one. A standard
 * title, "RIG - [KEY] Description" with an optional count, counts up and stays
 * as it is: "… Description" continues as "… Description 1", then "… 2". Any
 * other title is renamed to the standard form when a work is given, and the
 * next thread is "… 1"; with no work, "Foo" continues as "Foo 2".
 */
export function handoffTitles(currentTitle, work) {
    const title = currentTitle.trim();
    const standard = STANDARD_TITLE.exec(title);
    if (standard) {
        const [, key, description, count] = standard;
        return { next: `RIG - [${key}] ${description} ${count ? Number(count) + 1 : 1}` };
    }
    if (work) {
        const rename = `RIG - [${work.key}] ${work.description}`;
        return { rename, next: `${rename} 1` };
    }
    const numbered = /^(.*\S)\s+(\d+)$/.exec(title);
    return { next: numbered ? `${numbered[1]} ${Number(numbered[2]) + 1}` : `${title} 2` };
}

/** An error that says what went wrong and, when there is one, what fixes it. */
class Problem extends Error {
    constructor(message, fix) {
        super(message);
        this.fix = fix;
    }
}

function parseArgs(argv) {
    const [command, ...rest] = argv;
    const flags = { dryRun: false };
    for (let i = 0; i < rest.length; i++) {
        const arg = rest[i];
        if (arg === '--dry-run') flags.dryRun = true;
        else if (arg === '--prompt-file') flags.promptFile = rest[++i];
        else if (arg === '--thread') flags.thread = rest[++i];
        else if (arg === '--key') flags.key = rest[++i]?.trim();
        else if (arg === '--description') flags.description = rest[++i]?.trim();
        else throw new Problem(`unknown argument ${arg}`, USAGE);
    }
    if (!flags.key !== !flags.description) throw new Problem('--key and --description go together', USAGE);
    return { command, flags };
}

/** The origin of the running T3 Code server, once it has answered. */
async function serverOrigin() {
    const fix = 'Open T3 Code. This skill drives the server it runs on this machine.';
    const runtimePath = join(T3_HOME, 'userdata', 'server-runtime.json');
    if (!existsSync(runtimePath)) throw new Problem(`T3 Code is not running: ${runtimePath} is missing`, fix);
    const { origin } = JSON.parse(readFileSync(runtimePath, 'utf8'));
    try {
        await fetch(`${origin}/.well-known/t3/environment`);
    } catch {
        throw new Problem(`T3 Code is not running: nothing answers at ${origin}`, fix);
    }
    return origin;
}

/** The thread this Claude session belongs to, found through T3's own record of the session. */
async function currentThreadId() {
    const sessionId = process.env.CLAUDE_CODE_SESSION_ID;
    if (!sessionId) {
        throw new Problem('this is not a Claude session in T3 Code: CLAUDE_CODE_SESSION_ID is not set', 'Run the skill from a Claude thread in T3 Code, or pass --thread <id>.');
    }
    // node:sqlite prints an ExperimentalWarning on load; it is noise here.
    process.removeAllListeners('warning');
    let DatabaseSync;
    try {
        ({ DatabaseSync } = await import('node:sqlite'));
    } catch {
        throw new Problem(`finding the current thread needs Node 22.13 or later, and this is ${process.version}`, 'Install Node 22.13 or later (`nvm install 22`), or pass --thread <id>.');
    }
    const db = new DatabaseSync(join(T3_HOME, 'userdata', 'state.sqlite'), { readOnly: true });
    try {
        const rows = db
            .prepare('select thread_id from provider_session_runtime where resume_cursor_json like ?')
            .all(`%"resume":"${sessionId}"%`);
        if (rows.length !== 1) {
            throw new Problem(`expected one T3 thread for Claude session ${sessionId}, found ${rows.length}`, 'Pass --thread <id>. T3 may have changed how it records sessions.');
        }
        return rows[0].thread_id;
    } finally {
        db.close();
    }
}

/** A ten-minute bearer token, minted by T3's own CLI from its local auth store. */
function mintToken() {
    if (!existsSync(T3_EXE)) throw new Problem(`T3 Code is not installed at ${T3_EXE}`, 'Install T3 Code, or set T3_EXE to its executable.');
    const serverBin = join(T3_EXE, '..', 'resources', 'server.asar', 'apps', 'server', 'dist', 'bin.mjs');
    const fix = 'Update T3 Code. If it is current, its `auth session issue` command has changed and t3.mjs needs updating.';
    let out;
    try {
        out = execFileSync(T3_EXE, [serverBin, 'auth', 'session', 'issue', '--ttl', '10m', '--label', 'hf-t3-handoff', '--json'], {
            env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'pipe'],
        });
    } catch (error) {
        // error.message opens with the long command line, so prefer what the command said; when it never
        // started, it said nothing and error.message is all there is.
        const exit = error.status ?? error.signal ?? error.code;
        const said = [error.stderr, error.stdout].map((text) => String(text ?? '').trim()).filter(Boolean).join('\n') || error.message;
        throw new Problem(`T3's auth session issue failed (exit ${exit}): ${said.slice(0, 500)}`, fix);
    }
    const token = out.includes('{') ? JSON.parse(out.slice(out.indexOf('{'))).token : undefined;
    if (!token) throw new Problem('T3\'s auth session issue printed no token', fix);
    return token;
}

function api(origin, token) {
    return async (method, path, body) => {
        const response = await fetch(origin + path, {
            method,
            headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
            body: body ? JSON.stringify(body) : undefined,
        });
        const text = await response.text();
        if (!response.ok) throw new Problem(`${method} ${path} answered ${response.status}: ${text.slice(0, 500)}`);
        return text ? JSON.parse(text) : null;
    };
}

async function readThread(call, threadId) {
    return (await call('GET', `/api/orchestration/threads/${threadId}?turnLimit=1`)).thread;
}

function checkRig() {
    try {
        execSync('rig help', { stdio: 'ignore' });
    } catch {
        throw new Problem('rig is not on PATH', [
            'Install rig, then set it up:',
            '  PowerShell: irm https://raw.githubusercontent.com/hugoforte/rig/main/install.ps1 | iex',
            '  sh:         curl -fsSL https://raw.githubusercontent.com/hugoforte/rig/main/install.sh | sh',
            '  then:       rig prompt setup',
        ].join('\n'));
    }
}

function checkRigHandoffSkill() {
    if (!existsSync(RIG_HANDOFF_SKILL)) {
        throw new Problem(`the rig-handoff skill is missing: ${RIG_HANDOFF_SKILL}`, [
            'Link the skills rig ships into ~/.claude/skills:',
            '  with hugoforte/dotfiles: sh ai/install.sh --rig-skills-only',
            '  by hand:                 symlink each <rig checkout>/skills/* into ~/.claude/skills',
        ].join('\n'));
    }
}

/** Every requirement, each reported; returns whether all of them hold. */
async function check() {
    const results = [];
    // Runs one requirement and returns what its step returned, or undefined when it failed.
    const run = async (label, step) => {
        try {
            const value = await step();
            results.push({ ok: true, label });
            return value;
        } catch (error) {
            results.push({ ok: false, label, problem: error.message, fix: error.fix });
            return undefined;
        }
    };

    await run('rig is installed', checkRig);
    await run('the rig-handoff skill is linked', checkRigHandoffSkill);
    const origin = await run('T3 Code is running', serverOrigin);
    const token = await run('T3 Code issues a token', mintToken);
    const threadId = await run('this thread is found', currentThreadId);
    if (origin && token && threadId) await run('the T3 API reads this thread', () => readThread(api(origin, token), threadId));

    console.log('hf-t3-handoff needs:');
    for (const result of results) {
        console.log(`  ${result.ok ? 'ok  ' : 'FAIL'}  ${result.label}`);
        if (result.ok) continue;
        console.log(`        ${result.problem}`);
        if (result.fix) console.log(result.fix.split('\n').map((line) => `        ${line}`).join('\n'));
    }
    return results.every((result) => result.ok);
}

async function continueThread(flags) {
    if (!flags.promptFile) throw new Problem('--prompt-file <path> is required', USAGE);
    const prompt = readFileSync(flags.promptFile, 'utf8').trim();
    if (!prompt) throw new Problem(`${flags.promptFile} is empty`);

    const origin = await serverOrigin();
    const currentId = flags.thread ?? (await currentThreadId());
    const call = api(origin, mintToken());
    const current = await readThread(call, currentId);
    if (current.archivedAt) throw new Problem(`thread "${current.title}" is already archived`);

    const newId = randomUUID();
    const { rename, next: title } = handoffTitles(current.title, flags.key && { key: flags.key, description: flags.description });
    const archivedTitle = rename ?? current.title;
    const createdAt = new Date().toISOString();
    const create = {
        type: 'thread.create',
        commandId: randomUUID(),
        threadId: newId,
        projectId: current.projectId,
        title,
        modelSelection: current.modelSelection,
        runtimeMode: current.runtimeMode,
        interactionMode: current.interactionMode,
        branch: current.branch,
        worktreePath: current.worktreePath,
        createdAt,
    };
    const turn = {
        type: 'thread.turn.start',
        commandId: randomUUID(),
        threadId: newId,
        message: { messageId: randomUUID(), role: 'user', text: prompt, attachments: [] },
        runtimeMode: current.runtimeMode,
        interactionMode: current.interactionMode,
        createdAt,
    };

    if (flags.dryRun) {
        const renaming = rename ? `rename "${current.title}" to "${rename}", ` : '';
        console.log(`Would start "${title}" (${current.branch ?? current.worktreePath ?? 'project checkout'}, ${current.modelSelection.model}), ${renaming}and archive "${archivedTitle}".`);
        return;
    }

    await call('POST', '/api/orchestration/dispatch', create);
    await call('POST', '/api/orchestration/dispatch', turn);

    const deadline = Date.now() + TURN_START_TIMEOUT_MS;
    while (!(await readThread(call, newId)).latestTurn) {
        if (Date.now() > deadline) {
            throw new Problem(`"${title}" (${newId}) was created but its turn has not started after ${TURN_START_TIMEOUT_MS / 1000} s; "${current.title}" is left open`);
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    if (rename) {
        await call('POST', '/api/orchestration/dispatch', { type: 'thread.meta.update', commandId: randomUUID(), threadId: currentId, title: rename });
    }
    console.log(`Started "${title}" (${newId}). Archiving "${archivedTitle}".`);
    await call('POST', '/api/orchestration/dispatch', { type: 'thread.archive', commandId: randomUUID(), threadId: currentId });
}

// Skills are installed as symlinks, so compare real paths: argv[1] is the link.
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const { command, flags } = parseArgs(process.argv.slice(2));
        if (command === 'check') process.exitCode = (await check()) ? 0 : 1;
        else if (command === 'continue') await continueThread(flags);
        else throw new Problem(command ? `unknown command ${command}` : 'no command given', USAGE);
    } catch (error) {
        if (!(error instanceof Problem)) throw error;
        console.error(`t3: ${error.message}`);
        if (error.fix) console.error(error.fix);
        process.exitCode = 1;
    }
}
