---
name: hf-t3-handoff
description: Hand the current T3 Code thread over to a fresh one — write the handoff, start a new thread titled with the next number that runs it, and archive this one. Use when asked to hand off, continue in a new thread, or start over with a clean context inside T3 Code.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

# T3 handoff

A handoff, then a new T3 Code thread that picks it up, then this thread archived. The new thread gets this thread's project, branch or worktree, model, and access mode.

Threads of a rig work are titled `RIG - [KEY] Short description`, and each handoff counts up: `… Short description 1`, then `… 2`. A thread whose title is not in that form yet is renamed to it before it is archived.

## What it needs

- **rig**, set up, with its `rig-handoff` skill linked into `~/.claude/skills`.
- **T3 Code**, installed and running, with this skill run from a Claude thread in it.
- **Node 22.13 or later**, which can read T3's database to find the current thread.

## 0. Check the setup

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs check
```

It checks each requirement and prints `ok` or `FAIL`. Every failure comes with the command or step that fixes it. If any line fails, show the user the output as it is, offer to run the fixes that are commands, and stop: nothing has been committed or written yet. Do not start the handoff with a requirement missing, because a handoff that cannot open its new thread leaves the user to paste the prompt by hand.

## 1. Write the handoff

Follow the `rig-handoff` skill: read `~/.claude/skills/rig-handoff/SKILL.md` and do all of it, with this skill's arguments as the next session's focus. It covers both cases, inside a rig work and outside one, and it stops for the user where it says to. If it stopped, stop here too.

It ends with a prompt for a fresh session. That prompt is what the new thread receives: write it, exactly as it is and without the code fence, to a file in the OS temp directory.

## 2. Start the new thread

Inside a rig work, take the title's parts from `rig status`:

- **Key**: the first entry on its `tickets` line. A GitHub issue (`owner/repo#N`) is written as `repo#N`. A work with no ticket uses its id, the first word of `rig status`.
- **Description**: the work's title, cut to about five words, leading with the product when the work is about one (`IM unable to add product`). It must not end in a number, because a trailing number is read as the count.

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs continue --prompt-file <file> --key <key> --description "<description>" --dry-run
```

When the thread's title is already standard, the script keeps its key and description and ignores these two. Outside a rig work, leave both out: the title then counts up as it is, so "Foo" becomes "Foo 2".

The dry run names the thread it would start, any rename, and the thread it would archive. If any of it looks wrong, stop and tell the user. If the dry run is right, run the same command without `--dry-run`. This is the last tool call. Once the old thread is archived its session may stop, so anything you run after it can be cut off partway.

If the script fails, it prints the problem and its fix the same way `check` does.

## 3. Report

One or two lines: the new thread's title, and where the handoff was saved. If the script failed, quote its error. It archives this thread only after the new one's turn has started, so a failure always leaves this thread open. Say whether the new thread was created.

## How it works

`t3.mjs` drives the local T3 Code server through the HTTP API T3's own client uses: it mints a ten-minute bearer token with T3's `auth session issue` CLI, then dispatches `thread.create`, `thread.turn.start`, `thread.meta.update` (the rename) and `thread.archive` to `/api/orchestration/dispatch`. That API is internal to an alpha app and may change between T3 versions. When the script reports an unexpected response, it comes from that API, not from this skill.
