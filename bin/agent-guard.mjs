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
//
// Only commands are judged, never what they carry: heredoc bodies and quoted strings are taken
// out first, so a commit message or a PR body that mentions `sed -i` passes.
//
// ai/claude/settings.json registers it. A program on PATH rather than a script in ~/.claude, so
// the hook names it the same way on every machine.

import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const heredocOpener = /(?<!<)<<(?!<)-?\s*(['"]?)([\w.-]+)\1/g;
const interpreter = /^(\S*\/)?(python3?|py|node|perl|ruby|bash|sh)\b/;
const fileRedirect = /(^|\s)\d?>{1,2}\s*(?!&|\/dev\/null\b)\S/;
const inPlaceEdit = /^(sed\b.*\s(-[a-zA-Z]*i|--in-place)|perl\b.*\s-[a-zA-Z]*i)/;
const ghMerge = /^gh\s+(pr|stack)\s+merge\b/;
const ghApiMerge = /^gh\s+api\b(?=.*\/pulls\/[^/\s]+\/merge\b)(?=.*(-X\s*|--method[\s=]+)PUT\b)/;
const ghGraphqlMerge = /^gh\s+api\s+graphql\b.*\b(mergePullRequest|enablePullRequestAutoMerge)\b/;

const writeThroughShell = 'Write files and scripts with the Write tool and edit them with Edit, then run them. '
    + 'A heredoc or an in-place perl/sed edit loses quotes and backslashes on the way through Git Bash.';
const mergeIsHuman = 'Merging a pull request is the human\'s call. Go ahead only if they named this PR for merging in this session.';

// withoutHeredocBodies(command): the command with every heredoc's body and closing marker removed.
function withoutHeredocBodies(command) {
    const kept = [];
    let markers = [];
    for (const line of command.split('\n')) {
        if (markers.length) {
            if (line.trim() === markers[0]) markers.shift();
            continue;
        }
        kept.push(line);
        markers = [...line.matchAll(heredocOpener)].map((m) => m[2]);
    }
    return kept.join('\n');
}

const withoutQuotes = (text) => text.replace(/'[^']*'|"(?:[^"\\]|\\.)*"/g, '""');

// segments(text): each simple command, trimmed, so a pattern anchored with ^ is in command position.
const segments = (text) => text.split(/\n|;|&&|\|\||\||\$\(|\(|`/).map((s) => s.trim()).filter(Boolean);

// verdict(tool, command): { decision: 'deny' | 'ask', reason } or null to let the call through.
export function verdict(tool, command) {
    if (typeof command !== 'string') return null;
    const bodiless = withoutHeredocBodies(command);
    // The graphql query is itself a quoted string, so merges are read before quotes come out.
    const raw = segments(bodiless);
    if (raw.some((s) => ghGraphqlMerge.test(s))) return { decision: 'ask', reason: mergeIsHuman };
    const commands = segments(withoutQuotes(bodiless));
    if (commands.some((s) => ghMerge.test(s)) || raw.some((s) => ghApiMerge.test(s))) {
        return { decision: 'ask', reason: mergeIsHuman };
    }
    if (tool !== 'Bash') return null;
    for (const s of commands) {
        const heredoc = /(?<!<)<<(?!<)/.test(s);
        if (heredoc && (interpreter.test(s) || fileRedirect.test(s) || /^tee\b/.test(s))) {
            return { decision: 'deny', reason: writeThroughShell };
        }
        if (inPlaceEdit.test(s)) return { decision: 'deny', reason: writeThroughShell };
    }
    return null;
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
