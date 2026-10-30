#!/usr/bin/env node
// The parts of a T3 Code handoff the agent's t3-code MCP tools cannot do. A
// handoff on this computer goes through those tools; this script gives it the
// titles, and starts the next thread on another computer, whose T3 Code server
// the MCP tools do not reach.
//
//   node t3.mjs title --current <title> [--key <key> --description <text>]
//   node t3.mjs check [--to <computer> --from <file>]
//   node t3.mjs continue --to <computer> --from <file> --title <title> --prompt-file <path> [--dry-run]
//   node t3.mjs token [--ttl <ttl>]
//
// `title` prints the rename this thread needs, if any, and the next thread's
// title (see handoffTitles). `check` lists everything the handoff needs and how
// to fix what is missing. `continue` starts the next thread on the other
// computer and waits for its run to start; the agent then renames and archives
// this thread. `--from` is a JSON file the agent writes from its MCP tools:
// { "project": <t3_project_read>, "configuration": <t3_thread_configuration> }.
// `token` prints this computer's entry for another computer's COMPUTERS_FILE.
//
// It drives the other computer's server through the API T3's own web client
// uses: orchestration protocol 2, read over HTTP and commanded over its
// WebSocket RPC. That API is internal to a pre-1.0 app, so every call checks
// its answer and stops with the response it got rather than guessing.

import { execFileSync, execSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, realpathSync } from 'node:fs';
import { homedir, hostname } from 'node:os';
import { join, posix, win32 } from 'node:path';
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
    'usage: t3.mjs title --current <title> [--key <key> --description <text>]',
    '       t3.mjs check [--to <computer> --from <file>]',
    '       t3.mjs continue --to <computer> --from <file> --title <title> --prompt-file <path> [--dry-run]',
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
 * A git remote URL as T3 keys a repository: lower case, without `.git` or a
 * trailing slash, as `host/path` whether written as a URL or as `user@host:path`.
 * T3's own spelling of Azure DevOps remotes is not reproduced.
 */
export function remoteKey(url) {
    const normalized = url.trim().replace(/\/+$/, '').replace(/\.git$/i, '').toLowerCase();
    if (/^(?:ssh|https?|git):\/\//.test(normalized)) {
        try {
            const { hostname, pathname } = new URL(normalized);
            const segments = pathname.split('/').filter(Boolean);
            if (hostname && segments.length > 1) return `${hostname}/${segments.join('/')}`;
        } catch {
            return normalized;
        }
    }
    const scp = /^[a-z0-9._-]+@([^:/\s]+):([^/\s]+(?:\/[^/\s]+)+)$/.exec(normalized);
    return scp ? `${scp[1]}/${scp[2]}` : normalized;
}

/**
 * The repository key of the checkout at `folder`, read from its remote as T3
 * reads it: `upstream`, else `origin`. Undefined when it has neither.
 */
export function checkoutRepositoryKey(folder) {
    for (const remote of ['upstream', 'origin']) {
        try {
            const url = execFileSync('git', ['-C', folder, 'remote', 'get-url', remote], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
            if (url) return remoteKey(url);
        } catch {
            // No such remote, or no checkout there: try the next.
        }
    }
    return undefined;
}

/**
 * The project among another computer's that holds the same repository as this
 * one, or undefined when none or several do. Project ids differ per computer,
 * so the repository is what the two share; among several clones of it, the one
 * titled like this project is the match. `key` is this project's repository,
 * for when T3 has not said it.
 */
export function matchingProject(project, candidates, key = project.repositoryIdentity?.canonicalKey) {
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

export function parseArgs(argv) {
    const [command, ...rest] = argv;
    const flags = { dryRun: false };
    const named = { '--to': 'to', '--ttl': 'ttl', '--from': 'from', '--title': 'title', '--current': 'current', '--prompt-file': 'promptFile' };
    // A title is free text and may start with a dash; a computer or a file named so is a flag left without its value.
    const freeText = ['--title', '--current'];
    for (let i = 0; i < rest.length; i++) {
        const arg = rest[i];
        if (arg === '--dry-run') flags.dryRun = true;
        else if (named[arg]) {
            // A missing value must not fall back to this computer, or an empty title, without a word.
            const value = rest[++i]?.trim();
            if (!value || (value.startsWith('-') && !freeText.includes(arg))) throw new Problem(`${arg} needs a value`, USAGE);
            // T3's command line runs through cmd on Windows, so the ttl is kept to what cannot be a command.
            if (arg === '--ttl' && !/^[1-9]\d*\s*[a-z]+$/i.test(value)) throw new Problem(`--ttl must be a count and a unit such as 365d, not ${value}`, USAGE);
            flags[named[arg]] = value;
        }
        else if (arg === '--key') flags.key = rest[++i]?.trim();
        else if (arg === '--description') flags.description = rest[++i]?.trim();
        else throw new Problem(`unknown argument ${arg}`, USAGE);
    }
    if (!flags.key !== !flags.description) throw new Problem('--key and --description go together', USAGE);
    if (flags.to && !flags.from) throw new Problem('--to needs --from, the file of this thread\'s project and configuration', USAGE);
    return { command, flags };
}

/**
 * This thread's project and configuration, from the file the agent wrote out
 * of its t3_project_read and t3_thread_configuration answers.
 */
export function readFrom(path) {
    const fix = 'Write it as { "project": <t3_project_read>, "configuration": <t3_thread_configuration> }, each answer as the MCP tool gave it.';
    let from;
    try {
        from = JSON.parse(readFileSync(path, 'utf8'));
    } catch (error) {
        throw new Problem(`--from ${path} cannot be read as JSON: ${error.message}`, fix);
    }
    const { project, configuration } = from ?? {};
    const missing = [
        ['project.title', project?.title],
        ['project.workspaceRoot', project?.workspaceRoot],
        ['configuration.modelSelection.model', configuration?.modelSelection?.model],
        ['configuration.runtimeMode', configuration?.runtimeMode],
        ['configuration.interactionMode', configuration?.interactionMode],
    ].filter(([, value]) => !value).map(([name]) => name);
    if (missing.length) throw new Problem(`--from ${path} has no ${missing.join(', ')}`, fix);
    return { project, configuration };
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

/** Commanding another computer's T3 Code goes over a WebSocket, which Node has built in from 22.4. */
function checkWebSocket() {
    if (typeof WebSocket === 'undefined') {
        throw new Problem(`commanding T3 Code needs Node 22.4 or later, and this is ${process.version}`, 'Install Node 22.4 or later (`nvm install 22`).');
    }
}

/** Checks that a T3 Code server answers at `origin` and speaks this script's protocol. */
async function probe(origin, problem, fix) {
    let response;
    try {
        response = await fetch(`${origin}/.well-known/t3/environment`, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) });
    } catch {
        throw new Problem(problem, fix);
    }
    const environment = response.ok ? await response.json().catch(() => undefined) : undefined;
    // Something else answering, such as a proxy's error page, is no description of a T3 server.
    if (typeof environment?.serverVersion !== 'string') {
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
    return { name: known, server, projects: await readProjectsWithRepositories(server) };
}

/**
 * A bearer session lasting `ttl`, issued by T3's own CLI from its local auth
 * store, for another computer to hand off to this one with. It may read threads
 * and command them, and nothing else T3 can grant.
 */
function issueSession(ttl) {
    const cli = t3Cli(process.platform, process.env, T3_HOME);
    if (!existsSync(cli)) throw new Problem(`T3 Code's command line is missing: ${cli}`, 'Open T3 Code once, which writes it, or set T3CODE_CLI_PATH to it.');
    const fix = 'Update T3 Code. If it is current, its `auth session issue` command has changed and t3.mjs needs updating.';
    const args = ['auth', 'session', 'issue', '--ttl', ttl, '--label', 'hf-t3-handoff', '--scope', 'orchestration:read', '--scope', 'orchestration:operate', '--json'];
    const options = { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] };
    let out;
    try {
        // Windows runs a .cmd only through its shell, given one command line with each part quoted.
        out = process.platform === 'win32'
            ? execSync([cli, ...args].map((part) => `"${part}"`).join(' '), options)
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
 * One Effect RPC call over `socket`, a WebSocket to the server at `origin`, sent
 * once it opens: the call's value, or a Problem when the server fails it,
 * cannot take it, closes first or does not answer within `timeoutMs`.
 */
export function rpcOver(socket, origin, method, payload, timeoutMs = RPC_TIMEOUT_MS) {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Problem(`${method} on ${origin} had no answer after ${timeoutMs / 1000} s`)), timeoutMs);
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
}

/**
 * One T3 Code server: `get` reads over HTTP, `rpc` calls a method over its
 * WebSocket. `refusedFix` is what to do when it turns the token down.
 */
function api(origin, token, refusedFix) {
    const request = async (method, path) => {
        let response;
        let text;
        try {
            response = await fetch(origin + path, {
                method,
                headers: { authorization: `Bearer ${token}`, 'x-t3-orchestration-protocol': String(PROTOCOL) },
                signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
            });
            text = await response.text();
        } catch (error) {
            throw new Problem(`${method} ${origin}${path} failed: ${error.message}`);
        }
        if (!response.ok) {
            const refused = response.status === 401 || response.status === 403;
            // A server on another protocol answers 400 with nothing to say, or 426.
            const otherProtocol = (response.status === 400 && !text) || response.status === 426;
            throw new Problem(
                `${method} ${origin}${path} answered ${response.status}: ${text.slice(0, 500)}`,
                refused ? refusedFix : otherProtocol ? PROTOCOL_FIX : undefined,
            );
        }
        try {
            return text ? JSON.parse(text) : null;
        } catch {
            throw new Problem(`${method} ${origin}${path} answered with something that is not JSON: ${text.slice(0, 200)}`);
        }
    };

    const rpc = async (method, payload) => {
        checkWebSocket();
        const { ticket } = await request('POST', '/api/auth/websocket-ticket');
        const url = new URL(`/ws?orchestrationProtocol=${PROTOCOL}&wsTicket=${encodeURIComponent(ticket)}`, origin);
        url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
        const socket = new WebSocket(url);
        try {
            return await rpcOver(socket, origin, method, payload);
        } finally {
            socket.close();
        }
    };

    return { get: (path) => request('GET', path), rpc };
}

/** A thread as T3 projects it, with its runs. */
async function readThread(server, threadId) {
    const { projection } = await server.get(`/api/orchestration/threads/${encodeURIComponent(threadId)}/bounded`);
    return { ...projection.thread, runs: projection.runs };
}

async function readProjects(server) {
    return (await server.get('/api/orchestration/shell')).projects;
}

/**
 * A server's projects with their repositories. T3 answers with the repository
 * identity it has cached, which it keeps for a minute, and null where it has
 * none, starting a lookup that lands within moments. So while a project lacks
 * one, read again, a few times: a project with no remote never gains one.
 */
export async function readProjectsWithRepositories(server, { attempts = 5, delayMs = 500 } = {}) {
    let projects = await readProjects(server);
    for (let attempt = 1; attempt < attempts && projects.some((project) => !project.repositoryIdentity); attempt++) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        projects = await readProjects(server);
    }
    return projects;
}

/**
 * Where the next thread starts on another computer: its project for the same
 * repository as `project`, this thread's project as t3_project_read gave it.
 */
export function destination(project, there) {
    // T3 leaves the identity null until it has looked the remote up, and this computer can look itself.
    const repository = project.repositoryIdentity?.canonicalKey ?? checkoutRepositoryKey(project.workspaceRoot);
    if (!repository) {
        const here = reachableName(hostname());
        throw new Problem(
            `project "${project.title}" has no git remote on ${here} to find it by: ${project.workspaceRoot} has neither an upstream nor an origin`,
            `Add the repository's remote to ${project.workspaceRoot} on ${here} (git remote add origin <url>), then run this again.`,
        );
    }
    const match = matchingProject(project, there.projects, repository);
    if (!match) {
        const unknown = there.projects.filter((candidate) => !candidate.repositoryIdentity).map((candidate) => `"${candidate.title}"`);
        const unsaid = unknown.length ? `; T3 Code there did not say the repository of ${unknown.join(', ')}` : '';
        throw new Problem(
            `${there.name} has no one project for ${repository}, the repository of "${project.title}"${unsaid}`,
            `Add the repository as a project in T3 Code on ${there.name}. If several of its clones are projects there, title one "${project.title}".`,
        );
    }
    return { server: there.server, projectId: match.id, place: `${there.name}, ${match.workspaceRoot}` };
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
    if (flags.to) {
        await run('Node can command another computer', checkWebSocket);
        const from = await run(`--from ${flags.from} holds this thread's project and configuration`, () => readFrom(flags.from));
        const there = await run(`T3 Code on ${flags.to} answers and takes its token`, () => otherComputer(flags.to));
        if (from && there) await run(`${there.name} has this thread's project`, () => destination(from.project, there));
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

/** Prints the rename this thread needs, if any, and the next thread's title, as JSON. */
function printTitles(flags) {
    if (!flags.current) throw new Problem('--current <title> is required', USAGE);
    console.log(JSON.stringify(handoffTitles(flags.current, flags.key && { key: flags.key, description: flags.description })));
}

/**
 * The `orchestration.launchThread` that starts the next thread in `projectId`
 * on another computer, with this thread's model selection and modes. A branch
 * or worktree of this computer says nothing about the checkout there, so it
 * starts in the project's checkout. One call creates the thread there and
 * starts its first run with the prompt.
 */
export function launchCommand(configuration, projectId, title, prompt) {
    return {
        commandId: randomUUID(),
        threadId: randomUUID(),
        projectId,
        title,
        modelSelection: configuration.modelSelection,
        runtimeMode: configuration.runtimeMode,
        interactionMode: configuration.interactionMode,
        workspaceStrategy: { type: 'root' },
        initialMessage: { messageId: randomUUID(), text: prompt, attachments: [] },
    };
}

/** Starts the next thread on another computer and waits for its run to start; this thread is the agent's to close. */
async function continueThread(flags) {
    if (!flags.to) throw new Problem('continue starts a thread on another computer: --to <computer> is required. On this computer, the agent hands off with its t3-code MCP tools.', USAGE);
    if (!flags.title) throw new Problem('--title <title> is required: the next title `t3.mjs title` printed', USAGE);
    if (!flags.promptFile) throw new Problem('--prompt-file <path> is required', USAGE);
    const prompt = readFileSync(flags.promptFile, 'utf8').trim();
    if (!prompt) throw new Problem(`${flags.promptFile} is empty`);

    const { project, configuration } = readFrom(flags.from);
    const next = destination(project, await otherComputer(flags.to));
    const { title } = flags;
    const launch = launchCommand(configuration, next.projectId, title, prompt);
    const newId = launch.threadId;

    if (flags.dryRun) {
        console.log(`Would start "${title}" (${next.place}, ${configuration.modelSelection.model}).`);
        return;
    }

    // From here on a thread may exist, so every failure names it and leaves the current one open.
    const created = `"${title}" (${newId}; ${next.place})`;
    const leftOpen = 'this thread is left open';
    const lookFirst = 'Look for it in T3 Code before running this again, which would start another.';
    try {
        await next.server.rpc('orchestration.launchThread', launch);
    } catch (error) {
        throw new Problem(`launching ${created} failed, and it may have been created anyway: ${error.message}; ${leftOpen}`, lookFirst);
    }

    const deadline = Date.now() + TURN_START_TIMEOUT_MS;
    for (let lastError; ;) {
        let runs;
        try {
            ({ runs } = await readThread(next.server, newId));
            lastError = undefined;
        } catch (error) {
            // A read that fails once is no reason to give up on a thread that is starting.
            lastError = error;
        }
        try {
            if (runs && runStarted(runs)) break;
        } catch (error) {
            throw new Problem(`${created}: ${error.message}; ${leftOpen}`);
        }
        if (Date.now() > deadline) {
            const last = lastError ? ` (last read: ${lastError.message})` : '';
            throw new Problem(`${created} was launched but its run has not started after ${TURN_START_TIMEOUT_MS / 1000} s${last}; ${leftOpen}`, `It may still start, as when a setup script is slow. ${lookFirst}`);
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
    }

    console.log(`Started ${created}.`);
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
        if (command === 'title') printTitles(flags);
        else if (command === 'check') process.exitCode = (await check(flags)) ? 0 : 1;
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
