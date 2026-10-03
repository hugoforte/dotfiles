---
name: hf-t3-handoff
description: Hand the current T3 Code thread over to a fresh one — write the handoff, start a new thread titled with the next number that runs it, and archive this one. The new thread starts on this computer unless another is named. Use when asked to hand off, continue in a new thread, continue on another computer, or start over with a clean context inside T3 Code.
argument-hint: "What will the next session be used for? Name another computer to continue there."
disable-model-invocation: true
---

# T3 handoff

A handoff, then a new T3 Code thread that picks it up, then this thread archived. The new thread gets this thread's project, branch or worktree, model, and access mode.

The new thread starts on this computer. It starts on another one only when the user names it, in the arguments or earlier in the conversation ("hand off to the zenbook"): then every `t3.mjs` command below takes `--to <computer>`. Never pick another computer yourself. There the thread starts in the checkout of that computer's T3 project for the same repository, since a branch or worktree of this computer means nothing there.

Threads of a rig work are titled `RIG - [KEY] Short description`, and each handoff counts up: `… Short description 1`, then `… 2`. A thread whose title is not in that form yet is renamed to it before it is archived.

## What it needs

- **rig**, set up, with its `rig-handoff` skill linked into `~/.claude/skills`.
- **T3 Code**, installed and running, with this skill run from a Claude thread in it.
- **Node 22.13 or later**, which can read T3's database to find the current thread.
- **For another computer**: T3 Code running there with its server network-accessible, the repository added as a project in it, and that computer's entry in `~/.agent-secrets/hf-t3-handoff/computers.local.json` on this one. That file is a skill secret: `deploy-secrets.ps1` decrypts it from `ai/secrets/hf-t3-handoff/` in the personal overlay, so one copy lists every machine and reaches each of them by sync. Running `node ~/.claude/skills/hf-t3-handoff/t3.mjs token` on a computer prints its entry, token included, and the entry goes into the overlay's file with `sops edit` (see the `hf-dotfiles-secrets` skill), never into the decrypted copy. That is the user's to run and to paste: the token is a password, so never ask for it in chat and never print the file.

## 0. Check the setup

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs check [--to <computer>]
```

It checks each requirement and prints `ok` or `FAIL`. Every failure comes with the command or step that fixes it. If any line fails, show the user the output as it is, offer to run the fixes that are commands, and stop: nothing has been committed or written yet. Do not start the handoff with a requirement missing, because a handoff that cannot open its new thread leaves the user to paste the prompt by hand.

## 1. Write the handoff

Follow the `rig-handoff` skill: read `~/.claude/skills/rig-handoff/SKILL.md` and do all of it, with this skill's arguments as the next session's focus. It covers both cases, inside a rig work and outside one, and it stops for the user where it says to. If it stopped, stop here too.

It ends with a prompt for a fresh session. That prompt is what the new thread receives: write it, exactly as it is and without the code fence, to a file in the OS temp directory.

For another computer, the prompt must hold on a machine that has none of this one's files. Inside a rig work it already does: the branches are pushed and the prompt reads the handoff from the data root's remote. Outside one, nothing has left this machine, so before going on:

- Push the branch the work is on, and name it in the prompt as the branch to check out. Commit only tracked changes and ask the user first; if they would rather not push, stop.
- Put the handoff's whole text in the prompt in place of the path to it, which is a temp file only this computer has.

## 2. Start the new thread

Inside a rig work, take the title's parts from `rig status`:

- **Key**: the first entry on its `tickets` line. A GitHub issue (`owner/repo#N`) is written as `repo#N`. A work with no ticket uses its id, the first word of `rig status`.
- **Description**: the work's title, cut to about five words, leading with the product when the work is about one (`IM unable to add product`). It must not end in a number, because a trailing number is read as the count.

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs continue --prompt-file <file> --key <key> --description "<description>" [--to <computer>] --dry-run
```

When the thread's title is already standard, the script keeps its key and description and ignores these two. Outside a rig work, leave both out: the title then counts up as it is, so "Foo" becomes "Foo 2".

The dry run names the thread it would start and where (this thread's branch or worktree, or the other computer and the project folder there), any rename, and the thread it would archive. If any of it looks wrong, stop and tell the user. If the dry run is right, run the same command without `--dry-run`. This is the last tool call. Once the old thread is archived its session may stop, so anything you run after it can be cut off partway.

If the script fails, it prints the problem and its fix the same way `check` does.

## 3. Report

One or two lines: the new thread's title, the computer it is on when that is not this one, and where the handoff was saved. If the script failed, quote its error. It archives this thread only after the new one's turn has started, so a failure always leaves this thread open. Say whether the new thread was created.

## How it works

`t3.mjs` drives the local T3 Code server through the HTTP API T3's own client uses: it mints a ten-minute bearer token with T3's `auth session issue` CLI, then dispatches `thread.create`, `thread.turn.start`, `thread.meta.update` (the rename) and `thread.archive` to `/api/orchestration/dispatch`. With `--to`, the new thread's commands go to the other computer's server instead, at the origin and with the token its entry in `computers.local.json` gives, into the project whose repository matches this thread's project; the rename and the archive still go to this one. That API is internal to an alpha app and may change between T3 versions. When the script reports an unexpected response, it comes from that API, not from this skill.
