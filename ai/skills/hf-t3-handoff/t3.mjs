#!/usr/bin/env node
// Continues the current T3 Code thread in a new one: creates the next thread in
// the same project, branch and model, sends it the prompt, waits for its turn to
// start, then archives the current thread (renamed first when it was not yet
// standard; see handoffTitles). With --to, the next thread starts on another
// computer's T3 Code server instead, in its project for the same repository.
// With --project or --provider, it starts here in the project for that folder,
// or on that provider instance with the same model.
//
//   node t3.mjs check [--to <computer> | [--project <folder>] [--provider <instance-id>]] [--thread <id>]
//   node t3.mjs continue --prompt-file <path> [--to <computer> | [--project <folder>] [--provider <instance-id>]]
//                        [--key <key> --description <text>] [--thread <id>] [--dry-run]
//   node t3.mjs token [--ttl <ttl>]
//
// `check` lists everything the handoff needs and how to fix what is missing.
// `token` prints this computer's entry for another computer's COMPUTERS_FILE.
//
// It drives the local T3 Code server's HTTP API, which is what T3's own web
// client uses. That API is internal to an alpha app, so every call checks its
// answer and stops with the response it got rather than guessing.

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
const USAGE = [
    'usage: t3.mjs check [--to <computer> | [--project <folder>] [--provider <instance-id>]] [--thread <id>]',
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
 * T3 Code's executable and the server script packed beside it, where its
 * installer puts them on `platform`: under %LOCALAPPDATA% on Windows, in an app
 * bundle in /Applications on macOS, whose server is packed in the app's own
 * app.asar rather than a server.asar. `env.T3_EXE` names the executable
 * instead, and the server is found from it the same way.
 */
export function t3App(platform, env) {
    const server = ['apps', 'server', 'dist', 'bin.mjs'];
    if (platform === 'darwin') {
        const exe = env.T3_EXE ?? '/Applications/T3 Code (Alpha).app/Contents/MacOS/T3 Code (Alpha)';
        return { exe, serverBin: posix.join(exe, '..', '..', 'Resources', 'app.asar', ...server) };
    }
    const path = platform === 'win32' ? win32 : posix;
    const exe = env.T3_EXE ?? path.join(env.LOCALAPPDATA ?? '', 'Programs', 't3code', 'T3 Code (Alpha).exe');
    return { exe, serverBin: path.join(exe, '..', 'resources', 'server.asar', ...server) };
}

/**
 * The name another computer reaches this one by, from its host name: macOS adds
 * `.local`, its Bonjour name, which Tailscale's MagicDNS names leave off.
 */
export function reachableName(host) {
    return host.replace(/\.local$/i, '');
}

/**
 * A node of `tailscale status --json` by its MagicDNS name, the first label of
 * its DNSName, else by its HostName when that is a host name at all: Tailscale
 * reports a device's own label there, such as "Living Room TV".
 */
function tailscaleNodeName(node) {
    const label = node?.DNSName?.split('.')[0];
    if (label) return label;
    return /^[a-z0-9-]+$/i.test(node?.HostName ?? '') ? node.HostName : undefined;
}

/**
 * The name `token` puts in this computer's origin: its Tailscale name when
 * `status`, the parsed `tailscale status --json`, has one, since that is the
 * name the other computers resolve; else the reachable form of `host`.
 */
export function tokenName(status, host) {
    return tailscaleNodeName(status?.Self) ?? reachableName(host);
}

/** The Tailscale names of the peers in `status`, the parsed `tailscale status --json`. */
export function tailscalePeerNames(status) {
    return Object.values(status?.Peer ?? {}).map(tailscaleNodeName).filter(Boolean);
}

/** Whether a fetch failed because its host name does not resolve, rather than because nothing answered. */
export function doesNotResolve(error) {
    return ['ENOTFOUND', 'EAI_AGAIN'].includes(error?.cause?.code);
}

/** The problem for another computer's `origin` whose host does not resolve; `peers` are the Tailscale names, when Tailscale answered. */
export function unresolvedOrigin(name, origin, peers) {
    return new Problem(
        `${new URL(origin).hostname}, the host in ${name}'s origin ${origin}, does not resolve on this computer`,
        peers
            ? `Change the origin in that entry to a name this computer resolves. Tailscale sees: ${peers.join(', ') || 'no peers'}.`
            : 'Change the origin in that entry to a name or address this computer resolves, such as its Tailscale name.',
    );
}

/**
 * The T3 thread of a Claude session, from the ids of the threads whose session
 * record names it. T3 also keeps a row, `import:<instance>:<session>`, for a
 * session it imported; that one is the thread only when no other matches.
 */
export function sessionThread(sessionId, threadIds) {
    const live = threadIds.filter((id) => !id.startsWith('import:'));
    const candidates = live.length ? live : threadIds;
    if (candidates.length !== 1) {
        const found = candidates.length ? `${candidates.length}: ${candidates.join(', ')}` : '0';
        throw new Problem(`expected one T3 thread for Claude session ${sessionId}, found ${found}`, 'Pass --thread <id>. T3 may have changed how it records sessions.');
    }
    return candidates[0];
}

/**
 * `tailscale status --json`, parsed, or undefined when tailscale is not found or
 * does not answer. On macOS the app's own CLI is tried too, since the App Store
 * build puts none on PATH and an app started from the Dock gets launchd's PATH.
 */
function tailscaleStatus() {
    const clis = process.platform === 'darwin' ? ['tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale'] : ['tailscale'];
    for (const cli of clis) {
        try {
            return JSON.parse(execFileSync(cli, ['status', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: PROBE_TIMEOUT_MS }));
        } catch {
            // Not there, or not answering: try the next, then go without.
        }
    }
    return undefined;
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
        else if (['--to', '--ttl', '--project', '--provider', '--thread'].includes(arg)) {
            // A missing name must not fall back to this computer without a word.
            const value = rest[++i]?.trim();
            if (!value || value.startsWith('-')) throw new Problem(`${arg} needs a value`, USAGE);
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

/** Fails with `problem` when nothing answers at `origin`, or with what `unresolved` returns when its host does not resolve. */
export async function probe(origin, problem, fix, unresolved) {
    try {
        await fetch(`${origin}/.well-known/t3/environment`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) });
    } catch (error) {
        if (unresolved && doesNotResolve(error)) throw unresolved();
        throw new Problem(problem, fix);
    }
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
    await probe(
        origin,
        `T3 Code on ${known} does not answer at ${origin}`,
        'Open T3 Code on that computer, set its server to network-accessible, and check this computer reaches it (Tailscale up on both).',
        () => {
            const status = tailscaleStatus();
            return unresolvedOrigin(known, origin, status && tailscalePeerNames(status));
        },
    );
    const call = api(origin, token, `${known} refused its token in ${COMPUTERS_FILE}. ${entry}`);
    return { name: known, call, projects: await readProjects(call) };
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
        return sessionThread(sessionId, rows.map((row) => row.thread_id));
    } finally {
        db.close();
    }
}

/** A bearer session, ten minutes long unless told otherwise, issued by T3's own CLI from its local auth store. */
function issueSession(ttl = '10m') {
    const { exe, serverBin } = t3App(process.platform, process.env);
    if (!existsSync(exe)) throw new Problem(`T3 Code is not installed at ${exe}`, 'Install T3 Code, or set T3_EXE to its executable.');
    const fix = 'Update T3 Code. If it is current, its `auth session issue` command has changed and t3.mjs needs updating.';
    let out;
    try {
        out = execFileSync(exe, [serverBin, 'auth', 'session', 'issue', '--ttl', ttl, '--label', 'hf-t3-handoff', '--json'], {
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
    const session = out.includes('{') ? JSON.parse(out.slice(out.indexOf('{'))) : undefined;
    if (!session?.token) throw new Problem('T3\'s auth session issue printed no token', fix);
    return session;
}

/** Calls to one T3 Code server. `refusedFix` is what to do when it turns the token down. */
function api(origin, token, refusedFix) {
    return async (method, path, body) => {
        const response = await fetch(origin + path, {
            method,
            headers: { authorization: `Bearer ${token}`, ...(body ? { 'content-type': 'application/json' } : {}) },
            body: body ? JSON.stringify(body) : undefined,
        });
        const text = await response.text();
        if (!response.ok) {
            const refused = response.status === 401 || response.status === 403;
            throw new Problem(`${method} ${origin}${path} answered ${response.status}: ${text.slice(0, 500)}`, refused ? refusedFix : undefined);
        }
        return text ? JSON.parse(text) : null;
    };
}

async function readThread(call, threadId) {
    return (await call('GET', `/api/orchestration/threads/${threadId}?turnLimit=1`)).thread;
}

async function readProjects(call) {
    return (await call('GET', '/api/orchestration/shell')).projects;
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
export async function destination(call, current, there, target) {
    const { projectId, branch, worktreePath } = current;
    if (target && target.id !== projectId) {
        // A branch or worktree of one project says nothing about the checkout of another.
        return { call, projectId: target.id, branch: null, worktreePath: null, place: target.workspaceRoot };
    }
    if (!there) {
        const checkout = branch ?? worktreePath ?? 'project checkout';
        return { call, projectId, branch, worktreePath, place: target ? `${target.workspaceRoot}, ${checkout}` : checkout };
    }
    const project = (await readProjects(call)).find((candidate) => candidate.id === current.projectId);
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
    return { call: there.call, projectId: match.id, branch: null, worktreePath: null, place: `${there.name}, ${match.workspaceRoot}` };
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
    const call = origin && session && api(origin, session.token);
    const current = call && threadId && (await run('the T3 API reads this thread', () => readThread(call, threadId)));
    if (flags.to) {
        const there = await run(`T3 Code on ${flags.to} answers and takes its token`, () => otherComputer(flags.to));
        if (current && there) await run(`${there.name} has this thread's project`, () => destination(call, current, there));
    }
    if (flags.project && call) {
        await run(`T3 Code has a project for ${flags.project}`, async () => projectForFolder(flags.project, await readProjects(call)));
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
    const call = api(origin, issueSession().token);
    const current = await readThread(call, currentId);
    if (current.archivedAt) throw new Problem(`thread "${current.title}" is already archived`);
    const project = flags.project && projectForFolder(flags.project, await readProjects(call));
    const provider = flags.provider && providerInstance(flags.provider, readSettings(), current.modelSelection.instanceId);
    const next = await destination(call, current, flags.to && (await otherComputer(flags.to)), project);
    const modelSelection = modelSelectionOn(current.modelSelection, provider);

    const newId = randomUUID();
    const { rename, next: title } = handoffTitles(current.title, flags.key && { key: flags.key, description: flags.description });
    const archivedTitle = rename ?? current.title;
    const createdAt = new Date().toISOString();
    const create = {
        type: 'thread.create',
        commandId: randomUUID(),
        threadId: newId,
        projectId: next.projectId,
        title,
        modelSelection,
        runtimeMode: current.runtimeMode,
        interactionMode: current.interactionMode,
        branch: next.branch,
        worktreePath: next.worktreePath,
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
        const model = provider ? `${modelSelection.model} on ${provider.displayName}` : modelSelection.model;
        console.log(`Would start "${title}" (${next.place}, ${model}), ${renaming}and archive "${archivedTitle}".`);
        return;
    }

    await next.call('POST', '/api/orchestration/dispatch', create);
    await next.call('POST', '/api/orchestration/dispatch', turn);

    const deadline = Date.now() + TURN_START_TIMEOUT_MS;
    while (!(await readThread(next.call, newId)).latestTurn) {
        if (Date.now() > deadline) {
            throw new Problem(`"${title}" (${newId}; ${next.place}) was created but its turn has not started after ${TURN_START_TIMEOUT_MS / 1000} s; "${current.title}" is left open`);
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    if (rename) {
        await call('POST', '/api/orchestration/dispatch', { type: 'thread.meta.update', commandId: randomUUID(), threadId: currentId, title: rename });
    }
    console.log(`Started "${title}" (${newId}; ${next.place}). Archiving "${archivedTitle}".`);
    await call('POST', '/api/orchestration/dispatch', { type: 'thread.archive', commandId: randomUUID(), threadId: currentId });
}

/** Prints this computer's entry for another computer's COMPUTERS_FILE, with a token that lasts `ttl`. */
async function printToken(ttl = '365d') {
    const { port } = new URL(await serverOrigin());
    const { token, expiresAt } = issueSession(ttl);
    const status = tailscaleStatus();
    const name = tokenName(status, hostname());
    console.log(`This computer's entry for ${COMPUTERS_FILE} on the computer that hands off to it:\n`);
    console.log(`  ${JSON.stringify(name.toLowerCase())}: ${JSON.stringify({ origin: `http://${name}:${port}`, token })}\n`);
    console.log(`The token opens T3 Code on this computer until ${expiresAt}: keep it out of git and out of chat.`);
    console.log(tailscaleNodeName(status?.Self)
        ? 'The origin names this computer by its Tailscale name.'
        : 'Tailscale did not answer, so the origin names this computer by its host name, which the other computer may not resolve.');
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
