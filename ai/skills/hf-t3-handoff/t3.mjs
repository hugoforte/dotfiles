#!/usr/bin/env node
// Continues the current T3 Code thread in a new one: creates "<title> N+1" in the
// same project, branch and model, sends it the prompt, waits for its turn to
// start, then archives the current thread.
//
//   node t3.mjs continue --prompt-file <path> [--thread <id>] [--dry-run]
//
// It drives the local T3 Code server's HTTP API, which is what T3's own web
// client uses. That API is internal to an alpha app, so every call checks its
// answer and stops with the response it got rather than guessing.

import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const T3_HOME = process.env.T3CODE_HOME ?? join(homedir(), '.t3');
const TURN_START_TIMEOUT_MS = 60_000;

/** "Foo" becomes "Foo 2", and "Foo 2" becomes "Foo 3". */
export function nextTitle(title) {
    const numbered = /^(.*\S)\s+(\d+)$/.exec(title.trim());
    return numbered ? `${numbered[1]} ${Number(numbered[2]) + 1}` : `${title.trim()} 2`;
}

function fail(message) {
    console.error(`t3: ${message}`);
    process.exit(1);
}

function parseArgs(argv) {
    const [command, ...rest] = argv;
    const flags = { dryRun: false };
    for (let i = 0; i < rest.length; i++) {
        const arg = rest[i];
        if (arg === '--dry-run') flags.dryRun = true;
        else if (arg === '--prompt-file') flags.promptFile = rest[++i];
        else if (arg === '--thread') flags.thread = rest[++i];
        else fail(`unknown argument ${arg}`);
    }
    return { command, flags };
}

function serverOrigin() {
    const runtimePath = join(T3_HOME, 'userdata', 'server-runtime.json');
    if (!existsSync(runtimePath)) fail(`no running T3 Code server: ${runtimePath} is missing`);
    return JSON.parse(readFileSync(runtimePath, 'utf8')).origin;
}

/** The thread this Claude session belongs to, found through T3's own record of the session. */
async function currentThreadId() {
    const sessionId = process.env.CLAUDE_CODE_SESSION_ID;
    if (!sessionId) fail('CLAUDE_CODE_SESSION_ID is not set, so this is not a T3 Claude session; pass --thread <id>');
    // node:sqlite prints an ExperimentalWarning on load; it is noise here.
    process.removeAllListeners('warning');
    let DatabaseSync;
    try {
        ({ DatabaseSync } = await import('node:sqlite'));
    } catch {
        fail(`node:sqlite needs Node 22.13 or later (this is ${process.version}); pass --thread <id>`);
    }
    const db = new DatabaseSync(join(T3_HOME, 'userdata', 'state.sqlite'), { readOnly: true });
    try {
        const rows = db
            .prepare('select thread_id from provider_session_runtime where resume_cursor_json like ?')
            .all(`%"resume":"${sessionId}"%`);
        if (rows.length !== 1) fail(`expected one T3 thread for Claude session ${sessionId}, found ${rows.length}; pass --thread <id>`);
        return rows[0].thread_id;
    } finally {
        db.close();
    }
}

/** A ten-minute bearer token, minted by T3's own CLI from its local auth store. */
function mintToken() {
    const exe = process.env.T3_EXE ?? join(process.env.LOCALAPPDATA ?? '', 'Programs', 't3code', 'T3 Code (Alpha).exe');
    const serverBin = join(exe, '..', 'resources', 'server.asar', 'apps', 'server', 'dist', 'bin.mjs');
    if (!existsSync(exe)) fail(`T3 Code is not installed at ${exe}; set T3_EXE`);
    const out = execFileSync(exe, [serverBin, 'auth', 'session', 'issue', '--ttl', '10m', '--label', 'hf-t3-handoff', '--json'], {
        env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
        encoding: 'utf8',
    });
    const token = JSON.parse(out.slice(out.indexOf('{'))).token;
    if (!token) fail('t3 auth session issue printed no token');
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
        if (!response.ok) fail(`${method} ${path} answered ${response.status}: ${text.slice(0, 500)}`);
        return text ? JSON.parse(text) : null;
    };
}

async function readThread(call, threadId) {
    return (await call('GET', `/api/orchestration/threads/${threadId}?turnLimit=1`)).thread;
}

async function continueThread(flags) {
    if (!flags.promptFile) fail('--prompt-file <path> is required');
    const prompt = readFileSync(flags.promptFile, 'utf8').trim();
    if (!prompt) fail(`${flags.promptFile} is empty`);

    const origin = serverOrigin();
    const currentId = flags.thread ?? (await currentThreadId());
    const call = api(origin, mintToken());
    const current = await readThread(call, currentId);
    if (current.archivedAt) fail(`thread "${current.title}" is already archived`);

    const newId = randomUUID();
    const title = nextTitle(current.title);
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
        console.log(`Would start "${title}" (${current.branch ?? current.worktreePath ?? 'project checkout'}, ${current.modelSelection.model}) and archive "${current.title}".`);
        return;
    }

    await call('POST', '/api/orchestration/dispatch', create);
    await call('POST', '/api/orchestration/dispatch', turn);

    const deadline = Date.now() + TURN_START_TIMEOUT_MS;
    while (!(await readThread(call, newId)).latestTurn) {
        if (Date.now() > deadline) fail(`"${title}" (${newId}) was created but its turn has not started after ${TURN_START_TIMEOUT_MS / 1000} s; "${current.title}" is left open`);
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    console.log(`Started "${title}" (${newId}). Archiving "${current.title}".`);
    await call('POST', '/api/orchestration/dispatch', { type: 'thread.archive', commandId: randomUUID(), threadId: currentId });
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
    const { command, flags } = parseArgs(process.argv.slice(2));
    if (command !== 'continue') fail('usage: t3.mjs continue --prompt-file <path> [--thread <id>] [--dry-run]');
    await continueThread(flags);
}
