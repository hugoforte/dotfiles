#!/usr/bin/env node

// ticket-link-guard: Claude Code hooks that keep a ticket or a pull request from reaching Hugo
// bare, named without its full URL, and put nothing extra on the screen when they act.
//
//   - PreToolUse, on the tools whose text goes to a reader (send_to_user and t3_thread_send by
//     default): refuses the call before anything is sent, listing each bare reference, so only
//     the tool call is made again.
//   - UserPromptSubmit: reads Claude's last reply from the transcript and, when it left
//     references bare, adds one line of context to the prompt being sent, naming them.
//
// What counts as a reference, the tokens shaped like one that are not tickets, and the tools and
// fields read all come from ai/claude/ticket-links.jsonc, which documents them; the environment's
// TICKET_LINK_GUARD_CONFIG names another file in its place. Whatever the patterns, a reference is
// not bare when it is part of a URL, the text of a markdown link to a full URL (inline,
// reference-style or an autolink), in a code span or a fenced code block, on a commit message's
// own `Fixes #123` line (or Closes, Resolves), or when the text gives its URL anywhere.
//
// It reads no network and fails open: input it cannot use, a config it cannot read, or any other
// error lets the call or the prompt through, with a note on stderr.
//
// ai/claude/settings.json registers it as `node ticket-link-guard.mjs` in exec form, as
// agent-guard is, and ai/install.sh writes this checkout's absolute path to it into each live
// settings.json. It has no `onFailure`, so a hook that cannot start lets everything through.

import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync, realpathSync, statSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const defaultConfigPath = fileURLToPath(new URL('../ai/claude/ticket-links.jsonc', import.meta.url));

// parseJsonc(text): JSON with // and /* */ comments and trailing commas, parsed. Strings are
// copied whole, so what looks like a comment or a trailing comma inside one stays.
// A comment is matched whole, so a bracket inside one is not taken for the one that closes.
const trailingComma = /^,(?:\s|\/\/[^\n]*(?:\n|$)|\/\*(?:[^*]|\*(?!\/))*\*\/)*[}\]]/;
export function parseJsonc(text) {
    let out = '';
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (c === '"') {
            const end = /^"(?:[^"\\]|\\.)*"/.exec(text.slice(i));
            if (!end) throw new Error(`unterminated string at offset ${i}`);
            out += end[0];
            i += end[0].length - 1;
        } else if (c === '/' && text[i + 1] === '/') {
            while (i < text.length && text[i] !== '\n') i++;
            out += '\n';
        } else if (c === '/' && text[i + 1] === '*') {
            const close = text.indexOf('*/', i + 2);
            if (close < 0) throw new Error(`unterminated comment at offset ${i}`);
            i = close + 1;
        } else if (c === ',' && trailingComma.test(text.slice(i))) {
            continue;
        } else out += c;
    }
    return JSON.parse(out);
}

// compileConfig(raw, source): the config with its patterns compiled, or an error naming what in
// source is wrong.
export function compileConfig(raw, source = 'config') {
    const fail = (what) => {
        throw new Error(`${source}: ${what}`);
    };
    if (!raw || typeof raw !== 'object') fail('not an object');
    const list = (name) => {
        const value = raw[name] ?? [];
        if (!Array.isArray(value)) fail(`${name} is not an array`);
        return value;
    };
    const regex = (where, pattern, flags = '') => {
        if (typeof pattern !== 'string') fail(`${where} has no pattern`);
        try {
            return new RegExp(pattern, flags);
        } catch (error) {
            return fail(`${where}: ${error.message}`);
        }
    };
    const references = list('references').map((r, i) => {
        const where = `references[${i}] (${r?.name ?? 'unnamed'})`;
        if (r.linkedBy !== undefined && typeof r.linkedBy !== 'string') fail(`${where}: linkedBy is not a string`);
        return { name: r.name, regex: regex(where, r.pattern, `g${(r.flags ?? '').replace(/g/g, '')}`), linkedBy: r.linkedBy };
    });
    const allow = list('allow').map((a, i) => regex(`allow[${i}]`, a?.pattern));
    const shellTools = list('shellTools');
    const tools = raw.tools ?? {};
    if (typeof tools !== 'object' || Array.isArray(tools)) fail('tools is not an object');
    for (const [tool, fields] of Object.entries(tools)) {
        if (!Array.isArray(fields) || !fields.every((f) => typeof f === 'string')) fail(`tools.${tool} is not a list of fields`);
    }
    return { references, allow, shellTools, tools };
}

// loadConfig(path): the config at path, the environment's TICKET_LINK_GUARD_CONFIG, or the
// shipped one, compiled.
export function loadConfig(path = process.env.TICKET_LINK_GUARD_CONFIG || defaultConfigPath) {
    return compileConfig(parseJsonc(readFileSync(path, 'utf8')), path);
}

const url = /\b[a-z][a-z0-9+.-]*:\/\/[^\s<>`"]*/gi;
const fenceOpener = /^ {0,3}(`{3,}|~{3,})/;
const codeSpan = /(`+)[\s\S]*?(?<!`)\1(?!`)/g;
const inlineLink = /\[([^\]]*)\]\(\s*<?([^)\s>]*)>?(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;
const referenceLink = /\[[^\]]*\]\[[^\]]*\]/g;
const linkDefinition = /^ {0,3}\[[^\]]+\]:.*$/gm;
// A commit trailer, in the present tense; `[ \t]`, since a `\s` would run across blank lines.
const closingLine = /^[ \t]*(fixes|closes|resolves)[ \t]+([\w.-]+\/[\w.-]+)?#\d+[ \t]*$/gim;

// withoutFences(text): text with every fenced code block blanked; an unclosed fence runs to the end.
function withoutFences(text) {
    const kept = [];
    let open = null;
    for (const line of text.split('\n')) {
        const fence = fenceOpener.exec(line);
        if (open) {
            if (fence && fence[1][0] === open[0] && fence[1].length >= open.length && !line.slice(fence[0].length).trim()) open = null;
            kept.push('');
        } else if (fence && !(fence[1][0] === '`' && line.slice(fence[0].length).includes('`'))) {
            open = fence[1];
            kept.push('');
        } else kept.push(line);
    }
    return kept.join('\n');
}

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// linked(reference, match, urls): whether one of urls is the link reference's linkedBy names.
function linked(reference, match, urls) {
    if (!reference.linkedBy) return false;
    const groups = { ...match.groups, match: match[0] };
    const pattern = reference.linkedBy.replace(/\{(\w+)\}/g, (whole, name) => (name in groups ? escape(groups[name] ?? '') : whole));
    const regex = new RegExp(pattern, 'i');
    return urls.some((u) => regex.test(u));
}

// bareReferences(text, config): each reference text names without its URL, in order, once.
export function bareReferences(text, config) {
    if (typeof text !== 'string' || !text) return [];
    const urls = text.match(url) ?? [];
    let prose = withoutFences(text)
        .replace(codeSpan, ' ')
        .replace(inlineLink, (_, label, target) => (/^[a-z][a-z0-9+.-]*:\/\//i.test(target) ? ' ' : ` ${label} `))
        .replace(referenceLink, ' ')
        .replace(linkDefinition, ' ')
        .replace(url, ' ')
        .replace(closingLine, ' ');
    const found = [];
    for (const reference of config.references) {
        for (const match of prose.matchAll(reference.regex)) {
            if (!config.allow.some((a) => a.test(match[0])) && !linked(reference, match, urls)) {
                found.push({ index: match.index, ref: match[0] });
            }
        }
        prose = prose.replace(reference.regex, (m) => ' '.repeat(m.length));
    }
    return [...new Set(found.sort((a, b) => a.index - b.index).map((f) => f.ref))];
}

// strings(value): every string in value, however deep.
const strings = (value) => (typeof value === 'string' ? [value]
    : value && typeof value === 'object' ? Object.values(value).flatMap(strings) : []);

// fieldTexts(input, field): the strings at a dot path in input, where `name[]` reads each item.
function fieldTexts(input, field) {
    let values = [input];
    for (const part of field.split('.')) {
        const each = part.endsWith('[]');
        const name = each ? part.slice(0, -2) : part;
        values = values.flatMap((v) => {
            const next = v && typeof v === 'object' ? v[name] : undefined;
            return each ? (Array.isArray(next) ? next : []) : [next];
        });
    }
    return values.flatMap(strings);
}

// A shell command that sends a body to GitHub, and the ways it can carry one.
const ghBody = /\bgh\s+(?:(?:pr|issue)\s+(?:create|edit|comment|review)|api)\b/;
const quotedValue = String.raw`("(?:[^"\\\x60]|[\\\x60][\s\S])*"|'[^']*'|[^\s'"]+)`;
const bodyFlag = new RegExp(String.raw`(?:^|\s)(?:--body|-b)(?:=|\s+)${quotedValue}`, 'g');
const bodyField = new RegExp(String.raw`(?:^|\s)(?:-f|-F|--field|--raw-field)\s+body=${quotedValue}`, 'g');
const bodyFile = new RegExp(String.raw`(?:^|\s)(?:--body-file|-F)(?:=|\s+)${quotedValue}`, 'g');
const hereString = /@(['"])[ \t]*\r?\n([\s\S]*?)\r?\n\1@/g;
const heredocOpener = /<<-?\s*(['"]?)([\w.-]+)\1/;
const unquote = (v) => (v.startsWith('\'') ? v.slice(1, -1)
    : v.startsWith('"') ? v.slice(1, -1).replace(/[\\`]([\s\S])/g, '$1') : v);
const bodyFileLimit = 1024 * 1024;

// heredocBodies(command): the body of each heredoc in command; an unclosed one runs to the end.
function heredocBodies(command) {
    const bodies = [];
    let marker = null;
    let body = [];
    for (const line of command.split(/\r?\n/)) {
        if (marker) {
            if (line.trim() === marker) {
                bodies.push(body.join('\n'));
                marker = null;
                body = [];
            } else body.push(line);
            continue;
        }
        marker = heredocOpener.exec(line)?.[2] ?? null;
    }
    if (marker) bodies.push(body.join('\n'));
    return bodies;
}

// readBodyFile(path, cwd): a body file's text, or nothing when it is stdin, missing or too big.
// Git Bash's /d/… is tried as D:/… on Windows.
function readBodyFile(path, cwd) {
    if (path === '-' || /^\w+=/.test(path)) return [];
    let full = isAbsolute(path) ? path : resolve(typeof cwd === 'string' ? cwd : '.', path);
    if (!existsSync(full) && process.platform === 'win32' && /^\/[a-z]\//i.test(path)) full = `${path[1]}:${path.slice(2)}`;
    if (!existsSync(full) || statSync(full).size > bodyFileLimit) return [];
    return [readFileSync(full, 'utf8')];
}

// shellBodies(command, cwd): the bodies a gh command in command sends, never its title.
export function shellBodies(command, cwd) {
    if (typeof command !== 'string' || !ghBody.test(command)) return [];
    return [
        ...heredocBodies(command),
        ...[...command.matchAll(hereString)].map((m) => m[2]),
        ...[...command.matchAll(bodyFlag), ...command.matchAll(bodyField)].map((m) => unquote(m[1])),
        ...[...command.matchAll(bodyFile)].flatMap((m) => readBodyFile(unquote(m[1]), cwd)),
    ];
}

// lastReply(path): Claude's last reply in the transcript at path: the assistant's text after the
// last user entry, a tool result included, read from the transcript's last 2 MiB and passing
// over the prompt being sent. Null when the last turn ended in a tool call or there is no reply.
const transcriptTail = 2 * 1024 * 1024;
export function lastReply(path) {
    if (typeof path !== 'string' || !path || !existsSync(path)) return null;
    const fd = openSync(path, 'r');
    let tail;
    try {
        const size = fstatSync(fd).size;
        const start = Math.max(0, size - transcriptTail);
        const buffer = Buffer.alloc(size - start);
        readSync(fd, buffer, 0, buffer.length, start);
        tail = buffer.toString('utf8');
    } finally {
        closeSync(fd);
    }
    const texts = [];
    for (const line of tail.split('\n').reverse()) {
        let entry;
        try {
            entry = JSON.parse(line);
        } catch {
            continue;
        }
        if (!entry || typeof entry !== 'object' || entry.isSidechain) continue;
        const content = entry.message?.content;
        if (entry.type === 'user') {
            const toolResult = Array.isArray(content) && content.some((c) => c?.type === 'tool_result');
            if (texts.length || toolResult) break;
            continue;
        }
        if (entry.type !== 'assistant' || !Array.isArray(content)) continue;
        const text = content.filter((c) => c?.type === 'text' && typeof c.text === 'string').map((c) => c.text);
        if (text.length) texts.unshift(text.join('\n'));
        else if (!texts.length && content.some((c) => c?.type === 'tool_use')) break;
    }
    return texts.length ? texts.join('\n') : null;
}

// answer(input, config): the hook's answer to its parsed input, or null to let it through.
export function answer(input, config) {
    if (!input || typeof input !== 'object') return null;
    if (input.hook_event_name === 'PreToolUse') {
        const tool = input.tool_name;
        const texts = config.shellTools.includes(tool) ? shellBodies(input.tool_input?.command, input.cwd)
            : (config.tools[tool] ?? []).flatMap((field) => fieldTexts(input.tool_input, field));
        const refs = bareReferences(texts.join('\n\n'), config);
        if (!refs.length) return null;
        return {
            hookSpecificOutput: {
                hookEventName: 'PreToolUse',
                permissionDecision: 'deny',
                permissionDecisionReason: `This names ${refs.join(', ')} without a link. Rewrite every one as its full URL `
                    + '(the ticket\'s or the PR\'s own page), then make the call again. One that is not a ticket or a PR goes in backticks.',
            },
        };
    }
    if (input.hook_event_name === 'UserPromptSubmit') {
        const refs = bareReferences(lastReply(input.transcript_path), config);
        if (!refs.length) return null;
        return {
            hookSpecificOutput: {
                hookEventName: 'UserPromptSubmit',
                additionalContext: `Your last reply left these bare: ${refs.join(', ')}. Link every ticket and PR reference in full in this reply.`,
            },
        };
    }
    return null;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
    try {
        // Defensive: a hand-run test from Windows PowerShell 5.1 pipes a byte-order mark first.
        const input = JSON.parse(readFileSync(0, 'utf8').replace(/^\uFEFF/, ''));
        const result = answer(input, loadConfig());
        if (result) process.stdout.write(JSON.stringify(result));
    } catch (error) {
        process.stderr.write(`ticket-link-guard: ${error.message}; letting it through\n`);
    }
    process.exitCode = 0;
}
