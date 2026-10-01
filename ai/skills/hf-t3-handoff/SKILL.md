---
name: hf-t3-handoff
description: Hand the current T3 Code thread over to a fresh one — write the handoff, start a new thread titled with the next number that runs it, and archive this one. Use when asked to hand off, continue in a new thread, or start over with a clean context inside T3 Code.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

# T3 handoff

A handoff, then a new T3 Code thread that picks it up, then this thread archived. "Foo" continues as "Foo 2", and "Foo 2" as "Foo 3". The new thread gets this thread's project, branch or worktree, model, and access mode.

## 1. Write the handoff

Follow the `rig-handoff` skill: read `~/.claude/skills/rig-handoff/SKILL.md` and do all of it, with this skill's arguments as the next session's focus. It covers both cases, inside a rig work and outside one, and it stops for the user where it says to. If it stopped, stop here too.

It ends with a prompt for a fresh session. That prompt is what the new thread receives: write it, exactly as it is and without the code fence, to a file in the OS temp directory.

## 2. Start the new thread

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs continue --prompt-file <file> --dry-run
```

The dry run names the thread it would start and the one it would archive. If either looks wrong, stop and tell the user. If the dry run is right, run the same command without `--dry-run`. This is the last tool call. Once the old thread is archived its session may stop, so anything you run after it can be cut off partway.

The script finds this thread through `CLAUDE_CODE_SESSION_ID`. If it says it cannot, ask the user for the thread id and pass `--thread <id>`.

## 3. Report

One or two lines: the new thread's title, and where the handoff was saved. If the script failed, quote its error. It archives this thread only after the new one's turn has started, so a failure always leaves this thread open. Say whether the new thread was created.

## How it works

`t3.mjs` drives the local T3 Code server through the HTTP API T3's own client uses: it mints a ten-minute bearer token with T3's `auth session issue` CLI, then dispatches `thread.create`, `thread.turn.start` and `thread.archive` to `/api/orchestration/dispatch`. That API is internal to an alpha app and may change between T3 versions. When the script reports an unexpected response, it comes from that API, not from this skill.
