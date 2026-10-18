#!/usr/bin/env node
// Continues the current T3 Code thread in a new one: creates the next thread in
// the same project, branch and model, sends it the prompt, waits for its turn to
// start, then archives the current thread (renamed first when it was not yet
// standard; see handoffTitles). With --to, the next thread starts on another
// computer's T3 Code server instead, in its project for the same repository.
// With --project or --provider, it starts here in the project for that folder,
// or on that provider instance with the same model.
//
//   node t3.mjs check [--to <computer> | [--project <folder>] [--provider <instance-id>]]
//   node t3.mjs continue --prompt-file <path> [--to <computer> | [--project <folder>] [--provider <instance-id>]]
//                        [--key <key> --description <text>] [--thread <id>] [--dry-run]
//   node t3.mjs token [--ttl <ttl>]
//
// `check` lists everything the handoff needs and how to fix what is missing.
// `token` prints this computer's entry for another computer's COMPUTERS_FILE.
//
// It drives T3 Code's server through the API T3's own web client uses:
// orchestration protocol 2, read over HTTP and commanded over its WebSocket
// RPC. That API is internal to a pre-1.0 app, so every call checks its answer
// and stops with the response it got rather than guessing.

import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir, hostname } from 'node:os';
import { join, posix, resolve, win32 } from 'node:path';
import { fileURLToPath } from 'node:url';

const T3_HOME = process.env.T3CODE_HOME ?? join(homedir(), '.t3');
const RIG_HANDOFF_SKILL = join(homedir(), '.claude', 'skills', 'rig-handoff', 'SKILL.md');
// The computers --to can name, each with the origin of its T3 Code server and a token for it:
// { "<name>": { "origin": "http://<host>:3773", "token": "<token>" } }
const COMPUTERS_FILE = join(homedir(), '.agent-secrets', 'hf-t3-handoff', 'computers.local.json');
const TURN_START_TIMEOUT_MS = 60_000;
const PROBE_TIMEOUT_MS = 10_000;
const RPC_TIMEOUT_MS = 30_000;
// The orchestration protocol this script speaks; T3 refuses a client that speaks another.
const PROTOCOL = 2;
const PROTOCOL_FIX = `T3 Code there may not speak orchestration protocol ${PROTOCOL}: update T3 Code on that computer. If it is current, its API has changed and t3.mjs needs updating.`;
const USAGE = [
    'usage: t3.mjs check [--to <computer> | [--project <folder>] [--provider <instance-id>]]',
    '       t3.mjs continue --prompt-file <path> [--to <computer> | [--project <folder>] [--provider <instance-id>]]',
    '                       [--key <key> --description <text>] [--thread <id>] [--dry-run]',
    '       t3.mjs token [--ttl <ttl>]',
].join('\n');

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

/**
 * The project among another computer's that holds the same repository as this
 * one, or undefined when none or several do. Project ids differ per computer,
 * so the repository is what the two share; among several clones of it, the one
 * titled like this project is the match.
 */
export function matchingProject(project, candidates) {
    const key = project.repositoryIdentity?.canonicalKey;
    if (!key) return undefined;
    const clones = candidates.filter((candidate) => candidate.repositoryIdentity?.canonicalKey === key);
    if (clones.length === 1) return clones[0];
    const titled = clones.filter((candidate) => candidate.title === project.title);
    return titled.length === 1 ? titled[0] : undefined;
}

/**
 * T3 Code's command line: the launcher the desktop app writes into T3's home,
 * `bin/t3` (`bin\t3.cmd` on Windows), which runs the CLI bundled with whichever
 * channel of the app is installed. `env.T3CODE_CLI_PATH`, which T3 sets for its
 * agents, names it instead.
 */
export function t3Cli(platform, env, home) {
    if (env.T3CODE_CLI_PATH) return env.T3CODE_CLI_PATH;
    const path = platform === 'win32' ? win32 : posix;
    return path.join(home, 'bin', platform === 'win32' ? 't3.cmd' : 't3');
}

/**
 * Where the next thread runs on its project: in the worktree it is given,
 * else in the project's checkout, on the branch when it is given one.
 */
export function workspaceStrategy({ branch, worktreePath }) {
    const named = branch ? { branch } : {};
    return worktreePath ? { type: 'existing_worktree', worktreePath, ...named } : { type: 'root', ...named };
}

/**
 * Whether a thread's latest run has started, from its runs as T3 projects them.
 * A launch returns with the run already created and still preparing, so only a
 * run past that counts; one that ended before starting stops the handoff.
 */
export function runStarted(runs) {
    const status = runs.at(-1)?.status;
    if (['failed', 'cancelled', 'interrupted', 'rolled_back'].includes(status)) {
        throw new Problem(`the new thread's run ended ${status} before it started`);
    }
    return ['running', 'waiting', 'completed'].includes(status);
}

/** True when a server's environment says it speaks this script's protocol; a Problem otherwise. */
export function speaksProtocol(origin, environment) {
    // Hosts from before protocol negotiation leave the version out.
    const version = environment.orchestrationProtocolVersion ?? 1;
    if (version !== PROTOCOL) {
        throw new Problem(`T3 Code at ${origin} speaks orchestration protocol ${version}, and this script speaks ${PROTOCOL}`, PROTOCOL_FIX);
    }
    return true;
}

/** The value of an Effect RPC exit, or a Problem saying why the server failed the call. */
export function rpcValue(method, exit) {
    if (exit?._tag === 'Success') return exit.value;
    const causes = Array.isArray(exit?.cause) ? exit.cause : [];
    const reasons = causes.map((cause) => {
        const reason = cause.error ?? cause.defect ?? cause;
        return typeof reason === 'string' ? reason : reason.message ?? JSON.stringify(reason);
    });
    throw new Problem(`${method} failed: ${reasons.join('; ') || JSON.stringify(exit)}`);
}

/**
 * The name another computer reaches this one by, from its host name: macOS adds
 * `.local`, its Bonjour name, which Tailscale's MagicDNS names leave off.
 */
export function reachableName(host) {
    return host.replace(/\.local$/i, '');
}

/** An error that says what went wrong and, when there is one, what fixes it. */
class Problem extends Error {
    constructor(message, fix) {
        super(message);
        this.fix = fix;
    }
}

/** A folder made absolute. A bare drive, `D:`, is that drive's root rather than the folder last used on it. */
function absolute(folder) {
    return resolve(/^[a-z]:$/i.test(folder) ? `${folder}/` : folder);
}

/** A folder as T3 compares it: absolute, forward slashes, no trailing slash, and without case on Windows. */
function folderKey(folder) {
    const key = absolute(folder).replaceAll('\\', '/').replace(/\/+$/, '');
    return process.platform === 'win32' ? key.toLowerCase() : key;
}

/** The T3 project whose workspace root is `folder`, for --project. */
export function projectForFolder(folder, projects) {
    const key = folderKey(folder);
    const found = projects.filter((project) => project.workspaceRoot && folderKey(project.workspaceRoot) === key);
    if (found.length === 1) return found[0];
    if (!found.length) {
        throw new Problem(`T3 Code has no project for ${absolute(folder)}`, 'Add the folder as a project in T3 Code, then run this again.');
    }
    throw new Problem(
        `T3 Code has ${found.length} projects for ${absolute(folder)}: ${found.map((project) => `"${project.title}" (${project.id})`).join(', ')}`,
        'Remove all but one of them in T3 Code, then run this again.',
    );
}

/**
 * The provider instance `id` names in T3's settings, for --provider: one of
 * `providerInstances`, or a driver's default instance, whose id is the driver's
 * name. It must be enabled and, when the thread's own instance is known, run
 * the same driver as it, since the thread's model belongs to its driver.
 */
export function providerInstance(id, settings, currentInstanceId) {
    const configured = settings.providerInstances ?? {};
    const providers = settings.providers ?? {};
    const driverEnabled = (driver) => providers[driver]?.enabled ?? true;
    const instances = new Map(
        Object.entries(configured).map(([key, instance]) => {
            // As T3 reads it: off when the instance or its config says so, else what either
            // says, else what the driver says.
            const own = instance.enabled === false || instance.config?.enabled === false
                ? false
                : instance.enabled ?? instance.config?.enabled;
            return [key, { id: key, displayName: instance.displayName ?? key, driver: instance.driver, enabled: own ?? driverEnabled(instance.driver) }];
        }),
    );
    for (const driver of [...Object.values(configured).map((instance) => instance.driver), ...Object.keys(providers)]) {
        if (!instances.has(driver)) instances.set(driver, { id: driver, displayName: driver, driver, enabled: driverEnabled(driver) });
    }

    const enabled = [...instances.values()].filter((instance) => instance.enabled);
    const fix = `Pass one of them, or enable the instance in T3 Code's settings.`;
    const list = `the enabled ones are ${enabled.map((instance) => `${instance.id} (${instance.displayName})`).join(', ') || 'none'}`;
    const instance = instances.get(id);
    if (!instance) throw new Problem(`T3 Code has no provider instance "${id}"; ${list}`, fix);
    if (!instance.enabled) throw new Problem(`provider instance "${id}" (${instance.displayName}) is disabled in T3 Code; ${list}`, fix);
    // An instance removed since the thread started has no driver to compare.
    const currentDriver = instances.get(currentInstanceId)?.driver;
    if (currentDriver && instance.driver !== currentDriver) {
        const same = enabled.filter((candidate) => candidate.driver === currentDriver).map((candidate) => candidate.id);
        throw new Problem(
            `provider instance "${id}" runs ${instance.driver}, and this thread's model runs on ${currentDriver}`,
            `Pick an instance of ${currentDriver}: ${same.join(', ') || 'none is enabled'}.`,
        );
    }
    return { id: instance.id, displayName: instance.displayName, driver: instance.driver };
}

/** The next thread's model selection: this thread's, moved onto `provider` when one is given. */
export function modelSelectionOn(selection, provider) {
    return provider ? { ...selection, instanceId: provider.id } : selection;
}

function parseArgs(argv) {
    const [command, ...rest] = argv;
    const flags = { dryRun: false };
    for (let i = 0; i < rest.length; i++) {
        const arg = rest[i];
        if (arg === '--dry-run') flags.dryRun = true;
        else if (arg === '--prompt-file') flags.promptFile = rest[++i];
        else if (arg === '--thread') flags.thread = rest[++i];
        else if (['--to', '--ttl', '--project', '--provider'].includes(arg)) {
            // A missing name must not fall back to this computer without a word.
            const value = rest[++i]?.trim();
            if (!value || value.startsWith('-')) throw new Problem(`${arg} needs a value`, USAGE);
            // T3's command line runs through cmd on Windows, so the ttl is kept to what cannot be a command.
            if (arg === '--ttl' && !/^\d+[smhd]$/.test(value)) throw new Problem(`--ttl must be a count and a unit such as 365d, not ${value}`, USAGE);
            flags[arg.slice(2)] = value;
        }
        else if (arg === '--key') flags.key = rest[++i]?.trim();
        else if (arg === '--description') flags.description = rest[++i]?.trim();
        else throw new Problem(`unknown argument ${arg}`, USAGE);
    }
    if (!flags.key !== !flags.description) throw new Problem('--key and --description go together', USAGE);
    if (flags.to && (flags.project || flags.provider)) {
        throw new Problem('--project and --provider choose on this computer, so they do not go with --to', USAGE);
    }
    return { command, flags };
}

/** The origin of the running T3 Code server, once it has answered. */
async function serverOrigin() {
    const fix = 'Open T3 Code. This skill drives the server it runs on this machine.';
    const runtimePath = join(T3_HOME, 'userdata', 'server-runtime.json');
    if (!existsSync(runtimePath)) throw new Problem(`T3 Code is not running: ${runtimePath} is missing`, fix);
    const { origin } = JSON.parse(readFileSync(runtimePath, 'utf8'));
    await probe(origin, `T3 Code is not running: nothing answers at ${origin}`, fix);
    return origin;
}

/** Checks that a T3 Code server answers at `origin` and speaks this script's protocol. */
async function probe(origin, problem, fix) {
    let response;
    try {
        response = await fetch(`${origin}/.well-known/t3/environment`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) });
    } catch {
        throw new Problem(problem, fix);
    }
    let environment;
    try {
        environment = await response.json();
    } catch {
        throw new Problem(`T3 Code at ${origin} did not describe itself (${response.status})`, PROTOCOL_FIX);
    }
    speaksProtocol(origin, environment);
}

/** Another computer from COMPUTERS_FILE, once its T3 Code server has answered and taken its token. */
async function otherComputer(name) {
    const entry = 'Run `node ~/.claude/skills/hf-t3-handoff/t3.mjs token` on that computer: it prints its entry for this file.';
    if (!existsSync(COMPUTERS_FILE)) throw new Problem(`no other computer is set up: ${COMPUTERS_FILE} is missing`, entry);
    let computers;
    try {
        computers = JSON.parse(readFileSync(COMPUTERS_FILE, 'utf8'));
    } catch (error) {
        throw new Problem(`${COMPUTERS_FILE} is not JSON: ${error.message}`, 'It is decrypted from the overlay by deploy-secrets.ps1: fix it there with `sops edit` and deploy again.');
    }
    const known = Object.keys(computers).find((key) => key.toLowerCase() === name.toLowerCase());
    if (!known) throw new Problem(`${COMPUTERS_FILE} has no computer "${name}"; it has: ${Object.keys(computers).join(', ') || 'none'}`, entry);
    const { origin, token } = computers[known];
    if (!origin || !token) throw new Problem(`"${known}" in ${COMPUTERS_FILE} needs an origin and a token`, entry);
    await probe(origin, `T3 Code on ${known} does not answer at ${origin}`, 'Open T3 Code on that computer, set its server to network-accessible, and check this computer reaches it (Tailscale up on both).');
    const server = api(origin, token, `${known} refused its token in ${COMPUTERS_FILE}. ${entry}`);
    return { name: known, server, projects: await readProjects(server) };
}

/** The thread this Claude session belongs to, found through T3's own record of the session's provider thread. */
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
    const path = join(T3_HOME, 'userdata', 'statev2.sqlite');
    if (!existsSync(path)) {
        throw new Problem(`T3 Code's state is missing: ${path}`, `Update T3 Code: this skill needs the version that speaks orchestration protocol ${PROTOCOL}. Or pass --thread <id>.`);
    }
    const db = new DatabaseSync(path, { readOnly: true });
    try {
        const rows = db
            .prepare(`select distinct thread_id from orchestration_v2_projection_provider_threads
                      where json_extract(payload_json, '$.nativeThreadRef.nativeId') = ? and thread_id is not null`)
            .all(sessionId);
        if (rows.length !== 1) {
            throw new Problem(`expected one T3 thread for Claude session ${sessionId}, found ${rows.length}`, 'Pass --thread <id>. T3 may have changed how it records sessions.');
        }
        return rows[0].thread_id;
    } finally {
        db.close();
    }
}

/**
 * A bearer session, ten minutes long unless told otherwise, issued by T3's own
 * CLI from its local auth store. It may read threads and command them, and
 * nothing else T3 can grant.
 */
function issueSession(ttl = '10m') {
    const cli = t3Cli(process.platform, process.env, T3_HOME);
    if (!existsSync(cli)) throw new Problem(`T3 Code's command line is missing: ${cli}`, 'Open T3 Code once, which writes it, or set T3CODE_CLI_PATH to it.');
    const fix = 'Update T3 Code. If it is current, its `auth session issue` command has changed and t3.mjs needs updating.';
    const args = ['auth', 'session', 'issue', '--ttl', ttl, '--label', 'hf-t3-handoff', '--scope', 'orchestration:read', '--scope', 'orchestration:operate', '--json'];
    const options = { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] };
    let out;
    try {
        // Windows runs a .cmd only through its shell, given one command line with the path quoted.
        out = process.platform === 'win32'
            ? execSync(`"${cli}" ${args.join(' ')}`, options)
            : execFileSync(cli, args, options);
    } catch (error) {
        // error.message opens with the long command line, so prefer what the command said; when it never
        // started, it said nothing and error.message is all there is.
        const exit = error.status ?? error.signal ?? error.code;
        const said = [error.stderr, error.stdout].map((text) => String(text ?? '').trim()).filter(Boolean).join('\n') || error.message;
        throw new Problem(`T3's auth session issue failed (exit ${exit}): ${said.slice(0, 500)}`, fix);
    }
    const session = out.includes('{') ? JSON.parse(out.slice(out.indexOf('{'))) : undefined;
    if (!session?.token) throw new Problem('T3\'s auth session issue printed no token', fix);
    return session;
}

/**
 * One T3 Code server: `get` reads over HTTP, `rpc` calls a method over its
 * WebSocket. `refusedFix` is what to do when it turns the token down.
 */
function api(origin, token, refusedFix) {
    const request = async (method, path) => {
        const response = await fetch(origin + path, {
            method,
            headers: { authorization: `Bearer ${token}`, 'x-t3-orchestration-protocol': String(PROTOCOL) },
            signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
        });
        const text = await response.text();
        if (!response.ok) {
            const refused = response.status === 401 || response.status === 403;
            // A server on another protocol answers 400 with nothing to say, or 426.
            const otherProtocol = (response.status === 400 && !text) || response.status === 426;
            throw new Problem(
                `${method} ${origin}${path} answered ${response.status}: ${text.slice(0, 500)}`,
                refused ? refusedFix : otherProtocol ? PROTOCOL_FIX : undefined,
            );
        }
        return text ? JSON.parse(text) : null;
    };

    const rpc = async (method, payload) => {
        if (typeof WebSocket === 'undefined') {
            throw new Problem(`commanding T3 Code needs Node 22 or later, and this is ${process.version}`, 'Install Node 22.13 or later (`nvm install 22`).');
        }
        const { ticket } = await request('POST', '/api/auth/websocket-ticket');
        const url = new URL(`/ws?orchestrationProtocol=${PROTOCOL}&wsTicket=${encodeURIComponent(ticket)}`, origin);
        url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
        const socket = new WebSocket(url);
        try {
            return await new Promise((resolve, reject) => {
                const timer = setTimeout(() => reject(new Problem(`${method} on ${origin} had no answer after ${RPC_TIMEOUT_MS / 1000} s`)), RPC_TIMEOUT_MS);
                const settle = (settleWith) => (value) => {
                    clearTimeout(timer);
                    settleWith(value);
                };
                const fail = settle(reject);
                socket.addEventListener('open', () => {
                    socket.send(JSON.stringify({ _tag: 'Request', id: '1', tag: method, payload, headers: [] }));
                });
                socket.addEventListener('message', (event) => {
                    try {
                        const message = JSON.parse(event.data);
                        // A Defect or a protocol error is the server unable to take the request at all.
                        if (message._tag === 'Defect' || message._tag === 'ClientProtocolError') {
                            throw new Problem(`${origin} could not take ${method}: ${JSON.stringify(message).slice(0, 500)}`, PROTOCOL_FIX);
                        }
                        if (message._tag !== 'Exit' || String(message.requestId) !== '1') return;
                        settle(resolve)(rpcValue(method, message.exit));
                    } catch (error) {
                        fail(error instanceof Problem ? error : new Problem(`${origin} answered ${method} with a frame that is not JSON: ${String(event.data).slice(0, 200)}`));
                    }
                });
                // Settling twice is harmless: a close after the answer changes nothing.
                socket.addEventListener('error', () => fail(new Problem(`the WebSocket to ${origin} failed during ${method}`)));
                socket.addEventListener('close', ({ code, reason }) => {
                    fail(new Problem(`${origin} closed the WebSocket during ${method} (${code}${reason ? `: ${reason}` : ''})`));
                });
            });
        } finally {
            socket.close();
        }
    };

    return { get: (path) => request('GET', path), rpc };
}

/** A thread as T3 projects it, with its runs. */
async function readThread(server, threadId) {
    const { projection } = await server.get(`/api/orchestration/threads/${threadId}/bounded`);
    return { ...projection.thread, runs: projection.runs };
}

async function readProjects(server) {
    return (await server.get('/api/orchestration/shell')).projects;
}

/** One orchestration command, such as a rename or an archive. */
async function dispatch(server, command) {
    return server.rpc('orchestration.dispatchCommand', { commandId: randomUUID(), ...command });
}

/** T3's own settings, where its provider instances are configured. */
function readSettings() {
    const path = join(T3_HOME, 'userdata', 'settings.json');
    if (!existsSync(path)) throw new Problem(`T3 Code's settings are missing: ${path}`, 'Open T3 Code once, or set T3CODE_HOME to its home folder.');
    try {
        return JSON.parse(readFileSync(path, 'utf8'));
    } catch (error) {
        throw new Problem(`${path} is not JSON: ${error.message}`, 'Fix the file, or change a setting in T3 Code so it writes it again.');
    }
}

/**
 * Where the next thread starts: here, in the current thread's project and
 * checkout or in `target`, the project --project named, or on another computer,
 * in its project for the same repository.
 */
export async function destination(server, current, there, target) {
    const { projectId, branch, worktreePath } = current;
    if (target && target.id !== projectId) {
        // A branch or worktree of one project says nothing about the checkout of another.
        return { server, projectId: target.id, branch: null, worktreePath: null, place: target.workspaceRoot };
    }
    if (!there) {
        const checkout = branch ?? worktreePath ?? 'project checkout';
        return { server, projectId, branch, worktreePath, place: target ? `${target.workspaceRoot}, ${checkout}` : checkout };
    }
    const project = (await readProjects(server)).find((candidate) => candidate.id === current.projectId);
    if (!project) throw new Problem(`T3 Code does not list the project of this thread (${current.projectId})`);
    const match = matchingProject(project, there.projects);
    if (!match) {
        const repository = project.repositoryIdentity?.canonicalKey;
        throw new Problem(
            repository
                ? `${there.name} has no one project for ${repository}, the repository of "${project.title}"`
                : `project "${project.title}" has no git remote to find it by on ${there.name}`,
            `Add the repository as a project in T3 Code on ${there.name}. If several of its clones are projects there, title one "${project.title}".`,
        );
    }
    // A branch or worktree of this computer says nothing about the checkout there.
    return { server: there.server, projectId: match.id, branch: null, worktreePath: null, place: `${there.name}, ${match.workspaceRoot}` };
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
async function check(flags) {
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
    const session = await run('T3 Code issues a token', issueSession);
    const threadId = await run('this thread is found', async () => flags.thread ?? (await currentThreadId()));
    const server = origin && session && api(origin, session.token);
    const current = server && threadId && (await run('the T3 API reads this thread', () => readThread(server, threadId)));
    if (flags.to) {
        const there = await run(`T3 Code on ${flags.to} answers and takes its token`, () => otherComputer(flags.to));
        if (current && there) await run(`${there.name} has this thread's project`, () => destination(server, current, there));
    }
    if (flags.project && server) {
        await run(`T3 Code has a project for ${flags.project}`, async () => projectForFolder(flags.project, await readProjects(server)));
    }
    if (flags.provider) {
        const label = current ? 'is enabled and runs this thread\'s model' : 'is enabled';
        await run(`provider instance ${flags.provider} ${label}`, () => providerInstance(flags.provider, readSettings(), current?.modelSelection?.instanceId));
    }

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
    const server = api(origin, issueSession().token);
    const current = await readThread(server, currentId);
    if (current.archivedAt) throw new Problem(`thread "${current.title}" is already archived`);
    const project = flags.project && projectForFolder(flags.project, await readProjects(server));
    const provider = flags.provider && providerInstance(flags.provider, readSettings(), current.modelSelection.instanceId);
    const next = await destination(server, current, flags.to && (await otherComputer(flags.to)), project);
    const modelSelection = modelSelectionOn(current.modelSelection, provider);

    const newId = randomUUID();
    const { rename, next: title } = handoffTitles(current.title, flags.key && { key: flags.key, description: flags.description });
    const archivedTitle = rename ?? current.title;
    // One call creates the thread in its checkout and starts its first run with the prompt.
    const launch = {
        commandId: randomUUID(),
        threadId: newId,
        projectId: next.projectId,
        title,
        modelSelection,
        runtimeMode: current.runtimeMode,
        interactionMode: current.interactionMode,
        workspaceStrategy: workspaceStrategy(next),
        initialMessage: { messageId: randomUUID(), text: prompt, attachments: [] },
    };

    if (flags.dryRun) {
        const renaming = rename ? `rename "${current.title}" to "${rename}", ` : '';
        const model = provider ? `${modelSelection.model} on ${provider.displayName}` : modelSelection.model;
        console.log(`Would start "${title}" (${next.place}, ${model}), ${renaming}and archive "${archivedTitle}".`);
        return;
    }

    await next.server.rpc('orchestration.launchThread', launch);

    const deadline = Date.now() + TURN_START_TIMEOUT_MS;
    const started = async () => {
        try {
            return runStarted((await readThread(next.server, newId)).runs);
        } catch (error) {
            if (error instanceof Problem) error.message = `"${title}" (${newId}; ${next.place}): ${error.message}; "${current.title}" is left open`;
            throw error;
        }
    };
    while (!(await started())) {
        if (Date.now() > deadline) {
            throw new Problem(`"${title}" (${newId}; ${next.place}) was created but its turn has not started after ${TURN_START_TIMEOUT_MS / 1000} s; "${current.title}" is left open`);
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    if (rename) {
        await dispatch(server, { type: 'thread.metadata.update', threadId: currentId, title: rename });
    }
    console.log(`Started "${title}" (${newId}; ${next.place}). Archiving "${archivedTitle}".`);
    await dispatch(server, { type: 'thread.archive', threadId: currentId });
}

/** Prints this computer's entry for another computer's COMPUTERS_FILE, with a token that lasts `ttl`. */
async function printToken(ttl = '365d') {
    const { port } = new URL(await serverOrigin());
    const { token, expiresAt } = issueSession(ttl);
    const name = reachableName(hostname());
    console.log(`This computer's entry for ${COMPUTERS_FILE} on the computer that hands off to it:\n`);
    console.log(`  ${JSON.stringify(name.toLowerCase())}: ${JSON.stringify({ origin: `http://${name}:${port}`, token })}\n`);
    console.log(`The token opens T3 Code on this computer until ${expiresAt}: keep it out of git and out of chat.`);
    console.log('If the other computer knows this one by another name or address, change the origin to match.');
}

// Skills are installed as symlinks, so compare real paths: argv[1] is the link.
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        const { command, flags } = parseArgs(process.argv.slice(2));
        if (command === 'check') process.exitCode = (await check(flags)) ? 0 : 1;
        else if (command === 'continue') await continueThread(flags);
        else if (command === 'token') await printToken(flags.ttl);
        else throw new Problem(command ? `unknown command ${command}` : 'no command given', USAGE);
    } catch (error) {
        if (!(error instanceof Problem)) throw error;
        console.error(`t3: ${error.message}`);
        if (error.fix) console.error(error.fix);
        process.exitCode = 1;
    }
}
