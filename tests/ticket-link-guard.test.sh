#!/bin/sh

# Suite for bin/ticket-link-guard.mjs and its config, ai/claude/ticket-links.jsonc: which ticket
# and pull request references it calls bare, which tool calls it refuses before they send them,
# and when it reminds Claude, at the next prompt, that its last reply left some bare.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/assert.sh"

guard="$REPO_ROOT/bin/ticket-link-guard.mjs"
config="$REPO_ROOT/ai/claude/ticket-links.jsonc"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

nl='
'
fence='```'

# bare <text>: the references bareReferences finds in text with the shipped config,
# space-separated, or "none". The module is imported by a path from the environment: as an
# argument it would be argv[1], which makes it run as the hook and wait for JSON on stdin.
bare() {
    GUARD_MODULE="$guard" GUARD_TEXT="$1" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { bareReferences, loadConfig } = await import(pathToFileURL(process.env.GUARD_MODULE).href);
        const refs = bareReferences(process.env.GUARD_TEXT, loadConfig());
        console.log(refs.length ? refs.join(' ') : 'none');
    "
}

# hook <input> [config file]: runs the hook on input as its stdin and prints its exit code and
# its answer: deny, context (a UserPromptSubmit reminder), or allow when it printed nothing. Its
# stdout is kept in $work/out and its stderr in $work/stderr.
hook() {
    if [ -n "$2" ]; then
        printf '%s' "$1" | TICKET_LINK_GUARD_CONFIG="$2" node "$guard" > "$work/out" 2> "$work/stderr"
    else
        printf '%s' "$1" | node "$guard" > "$work/out" 2> "$work/stderr"
    fi
    rc=$?
    echo "$rc $(node -e "
        const s = require('node:fs').readFileSync(process.argv[1], 'utf8');
        if (!s.trim()) { console.log('allow'); process.exit(); }
        const o = JSON.parse(s).hookSpecificOutput;
        console.log(o.permissionDecision ?? (o.additionalContext ? 'context' : 'unknown'));
    " "$work/out")"
}

# said: the reason or the context the last hook run gave.
said() {
    node -e "
        const o = JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8')).hookSpecificOutput;
        console.log(o.permissionDecisionReason ?? o.additionalContext);
    " "$work/out"
}

# says <text> <part>: y when text holds part, else n. A case inside $( ) does not parse in the
# Mac's /bin/sh, bash 3.2, so the suite asks through this.
says() { case "$1" in *"$2"*) echo y ;; *) echo n ;; esac; }

# tool_input <tool> <tool_input JSON> [cwd]: a PreToolUse hook's input for that call.
tool_input() {
    GUARD_TOOL="$1" GUARD_INPUT="$2" GUARD_CWD="${3:-.}" node -e "
        process.stdout.write(JSON.stringify({
            session_id: 's', transcript_path: '', cwd: process.env.GUARD_CWD, hook_event_name: 'PreToolUse',
            tool_name: process.env.GUARD_TOOL, tool_input: JSON.parse(process.env.GUARD_INPUT),
        }));
    "
}

# message <text>: a send_to_user tool_input JSON whose message is text.
message() {
    GUARD_TEXT="$1" node -e "process.stdout.write(JSON.stringify({ message: process.env.GUARD_TEXT }))"
}

# Each reference pattern, found when it stands bare in prose.
assert_eq "a Jira key is bare" "KTLO-123" "$(bare "See KTLO-123 for the details.")"
assert_eq "a key of any project is bare" "CR-123" "$(bare "CR-123 is raised")"
assert_eq "a Linear key is bare" "VEC-42" "$(bare "Picked up VEC-42.")"
assert_eq "a key in parentheses is bare" "KTLO-12" "$(bare "the fix (KTLO-12) landed")"
assert_eq "a key in bold is bare" "KTLO-13" "$(bare "**KTLO-13** landed")"
assert_eq "a key in underscore emphasis is bare" "KTLO-14" "$(bare "_KTLO-14_ landed")"
assert_eq "a bare GitHub number is bare" "#123" "$(bare "Merged #123.")"
assert_eq "a number in underscore emphasis is bare" "#15" "$(bare "__#15__ landed")"
assert_eq "an owner/repo number is bare" "hugoforte/dotfiles#119" \
    "$(bare "hugoforte/dotfiles#119 is open")"
assert_eq "every reference is listed, in order" "KTLO-1 #22 hugoforte/rig#7" \
    "$(bare "KTLO-1 and #22, then hugoforte/rig#7")"
assert_eq "a reference named twice is listed once" "KTLO-1" "$(bare "KTLO-1, and again KTLO-1")"
assert_eq "a key whose link goes nowhere is bare" "KTLO-5" "$(bare "[KTLO-5](#notes)")"
assert_eq "a number in a line that only mentions fixing is bare" "#123" \
    "$(bare "This fixes #123 in passing.")"

# "#1"-style ordinals: a single digit counts only after a word that names a ticket or PR.
assert_eq "a single-digit ordinal is not a ticket" "none" "$(bare "the #1 cause, and option #2")"
assert_eq "a single-digit PR number is bare" "#3" "$(bare "PR #3 merged")"
assert_eq "a single-digit issue number is bare" "#4" "$(bare "see issue #4")"
assert_eq "a single-digit number straight after PR is bare" "#5" "$(bare "PR#5 merged")"
assert_eq "a number straight after PR is bare" "#12" "$(bare "PR#12 merged")"
assert_eq "a two-digit number is bare without a word before it" "#10" "$(bare "the #10 fix")"

# A reference that is a link, or is code, is not bare.
assert_eq "a key inside a URL is not bare" "none" \
    "$(bare "https://example.atlassian.net/browse/KTLO-123")"
assert_eq "a markdown link to the key's URL is not bare" "none" \
    "$(bare "[KTLO-123](https://example.atlassian.net/browse/KTLO-123)")"
assert_eq "a key as the text of a link to a full URL is not bare" "none" \
    "$(bare "[KTLO-7](https://example.com/x)")"
assert_eq "an owner/repo number as a link's text is not bare" "none" \
    "$(bare "[hugoforte/dotfiles#119](https://github.com/hugoforte/dotfiles/issues/119)")"
assert_eq "a reference-style link is not bare" "none" \
    "$(bare "[KTLO-8][jira]${nl}${nl}[jira]: https://example.atlassian.net/browse/KTLO-8")"
assert_eq "an autolink is not bare" "none" \
    "$(bare "<https://github.com/hugoforte/dotfiles/issues/119>")"
assert_eq "a number in a URL fragment is not bare" "none" "$(bare "https://example.com/page#10")"
assert_eq "a key in an inline code span is not bare" "none" "$(bare "Run \`rig new KTLO-123\`.")"
assert_eq "a key in a double-backtick code span is not bare" "none" \
    "$(bare "\`\`a \` KTLO-1\`\` here")"
assert_eq "a key in a fenced code block is not bare" "none" \
    "$(bare "Here:${nl}${fence}sh${nl}rig new KTLO-123 #44${nl}${fence}${nl}done")"
assert_eq "a key in a tilde fence is not bare" "none" \
    "$(bare "~~~${nl}KTLO-123${nl}~~~")"
assert_eq "a key after a fenced block is bare" "KTLO-9" \
    "$(bare "${fence}${nl}x${nl}${fence}${nl}KTLO-9")"
assert_eq "an unclosed fence runs to the end of the text" "none" \
    "$(bare "${fence}${nl}KTLO-123")"
assert_eq "a Fixes line is not bare" "none" "$(bare "Commit message:${nl}${nl}Fixes #123${nl}")"
assert_eq "a Fixes owner/repo line is not bare" "none" "$(bare "  Fixes hugoforte/dotfiles#119")"
assert_eq "a Closes line is not bare" "none" "$(bare "Closes #7")"
assert_eq "a status line in the past tense is bare" "#12 #45" "$(bare "Fixed #12${nl}Resolved #45")"

# A reference whose URL the text gives anywhere is not bare.
assert_eq "a key named next to its URL is not bare" "none" \
    "$(bare "KTLO-9: https://example.atlassian.net/browse/KTLO-9")"
assert_eq "a number named next to its issue's URL is not bare" "none" \
    "$(bare "#119 (https://github.com/hugoforte/dotfiles/issues/119)")"
assert_eq "an owner/repo number with its pull request URL is not bare" "none" \
    "$(bare "hugoforte/dotfiles#119, https://github.com/hugoforte/dotfiles/pull/119")"
assert_eq "an owner/repo number with another repo's URL is bare" "hugoforte/dotfiles#119" \
    "$(bare "hugoforte/dotfiles#119, https://github.com/hugoforte/rig/pull/119")"
assert_eq "a key named next to its Linear URL is not bare" "none" \
    "$(bare "VEC-9: https://linear.app/acme/issue/VEC-9/fix-the-thing")"
assert_eq "a key named next to a board URL selecting it is not bare" "none" \
    "$(bare "KTLO-9: https://example.atlassian.net/jira/software/projects/KTLO/boards/1?selectedIssue=KTLO-9")"
assert_eq "a key whose only URL is a branch named after it is bare" "KTLO-5" \
    "$(bare "KTLO-5 is on https://github.com/hugoforte/rig/tree/KTLO-5-foo")"
assert_eq "a key whose only URL is a compare view is bare" "KTLO-12" \
    "$(bare "KTLO-12, see https://github.com/o/r/compare/main...KTLO-12")"
assert_eq "a key whose URL names a longer number is bare" "KTLO-9" \
    "$(bare "KTLO-9: https://example.atlassian.net/browse/KTLO-99")"

# The allowlist, an entry at a time, and the other tokens shaped like keys that are not tickets.
assert_eq "hashes and ciphers are not tickets" "none" "$(bare "SHA-256, SHA-1, MD-5, AES-256, RSA-2048, CRC-32")"
assert_eq "encodings are not tickets" "none" "$(bare "UTF-8, not UTF-16 or BASE-64")"
assert_eq "standards are not tickets" "none" "$(bare "ISO-8601, RFC-7231, IEEE-754, ES-2015, PEP-8, WCAG-2")"
assert_eq "a CVE and a CWE are not tickets" "none" "$(bare "patched CVE-2024-1234 (CWE-79)")"
assert_eq "a time zone offset is not a ticket" "none" "$(bare "at 09:00 UTC-5, or GMT-8")"
assert_eq "protocols and hardware are not tickets" "none" "$(bare "HTTP-2 over TLS-1, IPV-6, USB-3, DDR-5")"
assert_eq "names with a number are not tickets" "none" "$(bare "GPT-4, COVID-19, IE-11")"
assert_eq "SHA3 is a hash, not a ticket" "none" "$(bare "SHA3-256")"
assert_eq "code pages are not tickets" "none" "$(bare "WINDOWS-1252, CP-1252, LATIN-1")"
assert_eq "named time zones are not tickets" "none" "$(bare "EST-5, PST-8, CET-1, AEST-10")"
assert_eq "fiscal years and audits are not tickets" "none" "$(bare "FY-2026, FY-26, SOC-2")"
assert_eq "platforms and formats are not tickets" "none" "$(bare "WSL-2, WIFI-6, PCIE-4, RJ-45, CAT-6, HTML-5, CSS-3")"
assert_eq "database error codes are not tickets" "none" "$(bare "ORA-00942")"
assert_eq "a header name is not a ticket" "none" "$(bare "X-Forwarded-For and X-Request-Id")"
assert_eq "a date is not a ticket" "none" "$(bare "observed 2026-11-26")"
assert_eq "a version is not a ticket" "none" "$(bare "v1.2-3 and node-22")"
assert_eq "a lowercase model id is not a ticket" "none" "$(bare "claude-opus-5-5")"
assert_eq "a key with one letter is not a ticket" "none" "$(bare "Q3-2026 and P-256")"
assert_eq "a key that starts a work id is not a ticket" "none" \
    "$(bare "work ABC-12-some-branch closed")"
assert_eq "a key in a path is not a ticket" "none" \
    "$(bare 'D:\\data\\work\\ABC-12 and feat/ABC-13')"
assert_eq "a key followed by a decimal is not a ticket" "none" "$(bare "ABC-1.2")"
assert_eq "an HTML entity is not a ticket" "none" "$(bare "&#123; is a brace")"
assert_eq "a number inside a path is not a ticket" "none" "$(bare "src/a/b#33")"

# Cost: a long reply, with runs of whitespace that blanking makes longer, is read well inside the
# 10-second timeout.
assert_eq "a 40,000-line code block and 5,000 references are read in under a second" "y" \
    "$(GUARD_MODULE="$guard" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { bareReferences, loadConfig } = await import(pathToFileURL(process.env.GUARD_MODULE).href);
        const config = loadConfig();
        const text = '\`\`\`\n' + 'x\n'.repeat(40000) + '\`\`\`\n' + 'KTLO-1 '.repeat(5000) + ' PR #3';
        const start = Date.now();
        const refs = bareReferences(text, config);
        console.log(Date.now() - start < 1000 && refs.join(' ') === 'KTLO-1 #3' ? 'y' : 'n');
    ")"

# The config: JSON with comments and trailing commas, and patterns of one's own.
assert_eq "comments and trailing commas go, and strings keep theirs" '{"a":"x//y /* z */","b":[1],"c":"\\d{2,}"}' \
    "$(GUARD_MODULE="$guard" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { parseJsonc } = await import(pathToFileURL(process.env.GUARD_MODULE).href);
        console.log(JSON.stringify(parseJsonc('{ \"a\": \"x//y /* z */\", // note\n /* block */ \"b\": [1, // last\n], \"c\": \"\\\\\\\\d{2,}\", }')));
    ")"
assert_eq "a comma before a comment that holds a bracket stays" '{"a":[],"b":1}' \
    "$(GUARD_MODULE="$guard" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { parseJsonc } = await import(pathToFileURL(process.env.GUARD_MODULE).href);
        console.log(JSON.stringify(parseJsonc('{ \"a\": [], // reads [] items\n /* or } */ \"b\": 1 }')));
    ")"
cat > "$work/own.jsonc" <<'EOF'
{
  // A tracker of one's own, and a token of it that is not a ticket.
  "references": [{ "name": "doc", "pattern": "\\bDOC(?<n>\\d+)\\b", "linkedBy": "/docs/{n}(?!\\d)" }],
  "allow": [{ "pattern": "^DOC0$" }],
  "tools": { "mcp__t3-code__send_to_user": ["message"] },
}
EOF
assert_eq "a config of one's own finds its own references" "0 deny" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "DOC12 and KTLO-1 and DOC0")")" "$work/own.jsonc")"
assert_eq "and lists only those" "ynn" "$(says "$(said)" DOC12)$(says "$(said)" KTLO)$(says "$(said)" DOC0)"
assert_eq "and its linkedBy finds a link" "0 allow" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "DOC12: https://example.com/docs/12")")" "$work/own.jsonc")"
printf '{ "references": [{ "name": "broken", "pattern": "(" }], "allow": [], "tools": {} }' > "$work/broken.jsonc"
assert_eq "a config whose pattern does not compile lets the call through" "0 allow" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "KTLO-1")")" "$work/broken.jsonc")"
assert_eq "and says why on stderr" "y" \
    "$(grep -q 'ticket-link-guard: .*broken' "$work/stderr" && echo y || echo n)"
assert_eq "a config that is missing lets the call through" "0 allow" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "KTLO-1")")" "$work/gone.jsonc")"

# PreToolUse, with the shipped config: the two tools whose text reaches a reader.
assert_eq "a message to the user with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "Done: KTLO-123.")")")"
hook "$(tool_input mcp__t3-code__send_to_user "$(message "KTLO-1 and #22 are done.")")" > /dev/null
assert_eq "the reason lists each reference" "y" "$(says "$(said)" 'KTLO-1, #22')"
assert_eq "the reason asks for full URLs" "y" "$(says "$(said)" 'full URL')"
assert_eq "a message to the user with only links goes" "0 allow" \
    "$(hook "$(tool_input mcp__t3-code__send_to_user "$(message "Done: [KTLO-123](https://example.atlassian.net/browse/KTLO-123).")")")"
assert_eq "a message to another thread with a bare number is refused" "0 deny" \
    "$(hook "$(tool_input mcp__t3-code__t3_thread_send '{"threadId":"t","message":"PR #12 is up"}')")"
assert_eq "a thread message's other fields are not read" "0 allow" \
    "$(hook "$(tool_input mcp__t3-code__t3_thread_send '{"threadId":"KTLO-1","message":"done"}')")"
assert_eq "a gh body is not read by default" "0 allow" \
    "$(hook "$(tool_input Bash '{"command":"gh pr create --title t --body \"see #12\""}')")"
assert_eq "a Jira comment is not read by default" "0 allow" \
    "$(hook "$(tool_input mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue '{"issueIdOrKey":"KTLO-1","commentBody":"see KTLO-2"}')")"
assert_eq "a call with no input goes" "0 allow" \
    "$(hook '{"hook_event_name":"PreToolUse","tool_name":"mcp__t3-code__send_to_user"}')"

# PreToolUse, with the config's commented-out entries turned on.
node -e "
    const fs = require('node:fs');
    const text = fs.readFileSync(process.argv[1], 'utf8').replace(/^(\s*)\/\/ (\"(mcp__|Bash|PowerShell))/gm, '\$1\$2');
    fs.writeFileSync(process.argv[2], text);
" "$config" "$work/all.jsonc"
all="$work/all.jsonc"
assert_eq "a Jira comment with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue '{"issueIdOrKey":"KTLO-1","commentBody":"see KTLO-2"}')" "$all")"
assert_eq "a Jira comment's issue key is not read" "0 allow" \
    "$(hook "$(tool_input mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue '{"issueIdOrKey":"KTLO-1","commentBody":"done"}')" "$all")"
assert_eq "a Jira description in ADF with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input mcp__claude_ai_Atlassian_Rovo__editJiraIssue '{"issueIdOrKey":"KTLO-1","fields":{"description":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"after KTLO-2"}]}]}}}')" "$all")"
assert_eq "a Jira description in ADF whose key is a link goes" "0 allow" \
    "$(hook "$(tool_input mcp__claude_ai_Atlassian_Rovo__editJiraIssue '{"issueIdOrKey":"KTLO-1","fields":{"description":{"type":"doc","content":[{"type":"text","text":"KTLO-2","marks":[{"type":"link","attrs":{"href":"https://example.atlassian.net/browse/KTLO-2"}}]}]}}}')" "$all")"
assert_eq "a review's line comment with a bare number is refused" "0 deny" \
    "$(hook "$(tool_input mcp__t3-code__pull_request_review '{"verdict":"comment","comments":[{"path":"a","line":1,"body":"as in #12"}]}')" "$all")"
assert_eq "a gh body with a bare number is refused, and its title is not read" "0 deny" \
    "$(hook "$(tool_input Bash '{"command":"gh pr create --title \"KTLO-1 fix\" --body \"see #12\""}')" "$all")"
assert_eq "and only the body's reference is listed" "yn" "$(says "$(said)" '#12')$(says "$(said)" KTLO-1)"
assert_eq "a gh body with only links goes" "0 allow" \
    "$(hook "$(tool_input Bash '{"command":"gh pr comment 5 --body \"see https://github.com/o/r/issues/12\""}')" "$all")"
assert_eq "a gh body's Fixes line goes" "0 allow" \
    "$(hook "$(tool_input Bash "$(GUARD_C="gh pr create --title t --body \"\$(cat <<'EOF'${nl}Summary${nl}${nl}Fixes #12${nl}EOF${nl})\"" node -e "process.stdout.write(JSON.stringify({ command: process.env.GUARD_C }))")")" "$all")"
assert_eq "a gh heredoc body with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input Bash "$(GUARD_C="gh issue create --title t --body-file - <<'EOF'${nl}after VEC-3${nl}EOF" node -e "process.stdout.write(JSON.stringify({ command: process.env.GUARD_C }))")")" "$all")"
printf 'Picks up KTLO-4.\n' > "$work/body.md"
assert_eq "a gh body file with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input Bash '{"command":"gh pr edit 3 --body-file body.md"}' "$work")" "$all")"
assert_eq "a gh body file that is missing goes" "0 allow" \
    "$(hook "$(tool_input Bash '{"command":"gh pr edit 3 --body-file gone.md"}' "$work")" "$all")"
assert_eq "a PowerShell here-string body with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input PowerShell "$(GUARD_C="gh pr create --title t --body @'${nl}after KTLO-5${nl}'@" node -e "process.stdout.write(JSON.stringify({ command: process.env.GUARD_C }))")")" "$all")"
assert_eq "a gh api body field with a bare key is refused" "0 deny" \
    "$(hook "$(tool_input Bash '{"command":"gh api repos/o/r/issues/1/comments -f body='"'"'after KTLO-6'"'"'"}')" "$all")"
assert_eq "a shell command that sends no gh body goes" "0 allow" \
    "$(hook "$(tool_input Bash '{"command":"git commit -m \"KTLO-7 fix\""}')" "$all")"

# UserPromptSubmit: the last reply in the transcript, the assistant's text after its last user
# entry (a tool result included), before the prompt being sent.
line() {
    GUARD_KIND="$1" GUARD_TEXT="$2" node -e "
        const k = process.env.GUARD_KIND, t = process.env.GUARD_TEXT;
        const entry = {
            prompt: { type: 'user', message: { role: 'user', content: t } },
            text: { type: 'assistant', message: { role: 'assistant', content: [{ type: 'text', text: t }] } },
            side: { type: 'assistant', isSidechain: true, message: { role: 'assistant', content: [{ type: 'text', text: t }] } },
            tool: { type: 'assistant', message: { role: 'assistant', content: [{ type: 'tool_use', id: 't', name: 'Bash', input: {} }] } },
            result: { type: 'user', message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 't', content: t }] } },
            meta: { type: 'user', isMeta: true, message: { role: 'user', content: t } },
            compact: { type: 'system', subtype: 'compact_boundary', content: 'Conversation compacted' },
            summary: { type: 'user', isCompactSummary: true, message: { role: 'user', content: t } },
        }[k];
        console.log(JSON.stringify(entry));
    "
}
prompt_input() {
    GUARD_TRANSCRIPT="$1" node -e "
        process.stdout.write(JSON.stringify({ hook_event_name: 'UserPromptSubmit', prompt: 'next', transcript_path: process.env.GUARD_TRANSCRIPT }));
    "
}
t="$work/transcript.jsonl"
{ line prompt go; line text "Looking at KTLO-2 first."; line tool; line result KTLO-3; line text "All done: VEC-1."; line text "And #44."; } > "$t"
assert_eq "a last reply with bare references gets a reminder" "0 context" "$(hook "$(prompt_input "$t")")"
assert_eq "which names them, from the final reply alone" \
    "Your last reply left these bare: VEC-1, #44. Link every ticket and PR reference in full in this reply. One that is not a ticket or a PR goes in backticks." "$(said)"
line prompt next >> "$t"
assert_eq "the prompt being sent, already in the transcript, is passed over" "0 context" "$(hook "$(prompt_input "$t")")"
{ line prompt go; line text "Done: [VEC-1](https://linear.app/x/issue/VEC-1)."; line prompt next; } > "$t"
assert_eq "a last reply with only links gets nothing" "0 allow" "$(hook "$(prompt_input "$t")")"
{ line prompt go; line text "Starting VEC-1."; line tool; } > "$t"
assert_eq "a turn that ended in a tool call gets nothing" "0 allow" "$(hook "$(prompt_input "$t")")"
{ line prompt go; line text "Done."; line side "Subagent: VEC-1."; } > "$t"
assert_eq "a subagent's text is not the last reply" "0 allow" "$(hook "$(prompt_input "$t")")"
assert_eq "a missing transcript gets nothing" "0 allow" "$(hook "$(prompt_input "$work/gone.jsonl")")"
{ line prompt go; line text "Done: VEC-1."; line prompt "stop there"; } > "$t"
assert_eq "a reply from before an unanswered prompt is not the last reply" "0 allow" "$(hook "$(prompt_input "$t")")"
{ line prompt go; line text "Done: VEC-1."; line compact; line summary "Earlier: VEC-1 was done."; } > "$t"
assert_eq "a reply from before a compaction is not the last reply" "0 allow" "$(hook "$(prompt_input "$t")")"
{ line prompt go; line text "Done: VEC-1."; line meta "a reminder"; line prompt next; } > "$t"
assert_eq "an entry the harness added after the reply is passed over" "0 context" "$(hook "$(prompt_input "$t")")"
node -e "
    const fs = require('node:fs');
    const lines = fs.readFileSync(process.argv[1], 'utf8').trim().split('\n');
    fs.writeFileSync(process.argv[1], '﻿' + lines.join('\r\n') + '\r\n');
" "$t"
assert_eq "a transcript with CRLF line ends and a byte-order mark is read" "0 context" "$(hook "$(prompt_input "$t")")"

# Input it cannot use lets everything through.
assert_eq "input that is not JSON lets it through" "0 allow" "$(hook "not json")"
assert_eq "empty input lets it through" "0 allow" "$(hook "")"
assert_eq "input that is not an object lets it through" "0 allow" "$(hook "null")"
assert_eq "another event is let through" "0 allow" \
    "$(hook '{"hook_event_name":"Stop","last_assistant_message":"KTLO-1"}')"

# The settings fragment: PreToolUse on exactly the config's tools, UserPromptSubmit, both in exec
# form as agent-guard is, with a short timeout and no onFailure, so a hook that cannot start lets
# everything through; and no Stop hook.
fragment="$REPO_ROOT/ai/claude/settings.json"
ours='select(.command == "node" and .args[0] == "ticket-link-guard.mjs")'
assert_eq "the PreToolUse matcher names exactly the config's tools" \
    "$(GUARD_MODULE="$guard" node --input-type=module -e "
        import { pathToFileURL } from 'node:url';
        const { loadConfig } = await import(pathToFileURL(process.env.GUARD_MODULE).href);
        const c = loadConfig();
        console.log([...Object.keys(c.tools), ...c.shellTools].sort().join('|'));
    ")" \
    "$(jq -r "[.hooks.PreToolUse[] | select(any(.hooks[]; $ours)) | .matcher | split(\"|\")[]] | sort | join(\"|\")" "$fragment")"
assert_eq "the hook is registered for UserPromptSubmit" "1" \
    "$(jq "[.hooks.UserPromptSubmit[]?.hooks[]? | $ours] | length" "$fragment")"
assert_eq "no Stop hook is registered" "0" "$(jq "[.hooks.Stop[]?.hooks[]? | $ours] | length" "$fragment")"
assert_eq "each registration has a short timeout and no onFailure" "y" \
    "$(jq -r "[.hooks[][].hooks[] | $ours] | if length == 2 and all(.timeout <= 10 and .onFailure == null) then \"y\" else \"n\" end" "$fragment")"

assert_summary "ticket-link-guard"
