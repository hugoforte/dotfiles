---
name: hf-t3-handoff
description: Hand the current T3 Code thread over to a fresh one — write the handoff, start a new thread titled with the next number that runs it, and archive this one. The new thread starts on this computer, in this project and on this provider instance, unless another is named. Use when asked to hand off, continue in a new thread, continue on another computer, in another project or on another provider instance, or start over with a clean context inside T3 Code.
argument-hint: "What will the next session be used for? Name another computer, project folder or provider instance to continue there."
disable-model-invocation: true
---

# T3 handoff

A handoff, then a new T3 Code thread that picks it up, then this thread archived. The new thread gets this thread's project, branch or worktree, model, provider instance, and access mode, unless the user names another project or provider instance.

The new thread starts on this computer. It starts on another one only when the user names it, in the arguments or earlier in the conversation ("hand off to the zenbook"): then every `t3.mjs` command below takes `--to <computer>`. Never pick another computer yourself. There the thread starts in the checkout of that computer's T3 project for the same repository, since a branch or worktree of this computer means nothing there.

The same goes for another project or another provider instance on this computer, such as a thread started in the wrong project or under the wrong Claude account. Only when the user names them, every `t3.mjs` command below takes `--project <folder>`, the folder of the T3 project to start in, or `--provider <instance-id>`, or both; neither goes with `--to`. In another project the thread starts in that project's checkout, since this thread's branch or worktree belongs to this one. On another instance it keeps the model and its options. Instance ids are the keys of `providerInstances` in `~/.t3/userdata/settings.json`, such as `claudeAgent_work`; when the user names an instance by its display name, run `check --provider <your best guess>`, which lists every enabled instance with its display name when the guess is wrong.

Threads of a rig work are titled `RIG - [KEY] Short description`, and each handoff counts up: `… Short description 1`, then `… 2`. A thread whose title is not in that form yet is renamed to it before it is archived.

## What it needs

- **rig**, set up, with its `rig-handoff` skill linked into `~/.claude/skills`.
- **T3 Code**, installed and running, with this skill run from a Claude thread in it. On Windows it is found in `%LOCALAPPDATA%\Programs\t3code`, on macOS as `/Applications/T3 Code (Alpha).app`; set `T3_EXE` to its executable when it is elsewhere.
- **Node 22.13 or later**, which can read T3's database to find the current thread.
- **For another computer**: T3 Code running there with its server network-accessible, the repository added as a project in it, and that computer's entry in `~/.agent-secrets/hf-t3-handoff/computers.local.json` on this one. That file is a skill secret: `deploy-secrets.ps1` decrypts it from `ai/secrets/hf-t3-handoff/` in the personal overlay, so one copy lists every machine and reaches each of them by sync. Running `node ~/.claude/skills/hf-t3-handoff/t3.mjs token` on a computer prints its entry, token included. The entry's origin names the computer by its Tailscale MagicDNS name when `tailscale` is on PATH (the first label of `Self.DNSName` in `tailscale status --json`, else its `Self.HostName`), since that is the name the other computers resolve, and by its host name without macOS's `.local` otherwise. The entry goes into the overlay's file with `sops edit` (see the `hf-dotfiles-secrets` skill), never into the decrypted copy. That is the user's to run and to paste: the token is a password, so never ask for it in chat and never print the file.

## 0. Check the setup

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs check [--to <computer> | [--project <folder>] [--provider <instance-id>]] [--thread <id>]
```

It checks each requirement and prints `ok` or `FAIL`. Every failure comes with the command or step that fixes it. When the other computer's origin names a host this one cannot resolve, it says so and lists the Tailscale peers it sees, so the entry can be corrected. When it cannot tell which thread this is, its fix is `--thread <id>`, which `check` takes as `continue` does. If any line fails, show the user the output as it is, offer to run the fixes that are commands, and stop: nothing has been committed or written yet. Do not start the handoff with a requirement missing, because a handoff that cannot open its new thread leaves the user to paste the prompt by hand.

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
node ~/.claude/skills/hf-t3-handoff/t3.mjs continue --prompt-file <file> --key <key> --description "<description>" [--to <computer> | [--project <folder>] [--provider <instance-id>]] --dry-run
```

When the thread's title is already standard, the script keeps its key and description and ignores these two. Outside a rig work, leave both out: the title then counts up as it is, so "Foo" becomes "Foo 2".

The dry run names the thread it would start and where (this thread's branch or worktree, the other computer and the project folder there, or the folder `--project` named), its model and, with `--provider`, the instance's display name, any rename, and the thread it would archive. If any of it looks wrong, stop and tell the user. If the dry run is right, run the same command without `--dry-run`. This is the last tool call. Once the old thread is archived its session may stop, so anything you run after it can be cut off partway.

If the script fails, it prints the problem and its fix the same way `check` does.

## 3. Report

One or two lines: the new thread's title, the computer it is on when that is not this one, and where the handoff was saved. If the script failed, quote its error. It archives this thread only after the new one's turn has started, so a failure always leaves this thread open. Say whether the new thread was created.

## How it works

`t3.mjs` drives the local T3 Code server through the HTTP API T3's own client uses: it mints a ten-minute bearer token with T3's `auth session issue` CLI, then dispatches `thread.create`, `thread.turn.start`, `thread.meta.update` (the rename) and `thread.archive` to `/api/orchestration/dispatch`. With `--to`, the new thread's commands go to the other computer's server instead, at the origin and with the token its entry in `computers.local.json` gives, into the project whose repository matches this thread's project; the rename and the archive still go to this one. `--project` picks the project whose workspace root is the folder, compared as an absolute path with either slash (and without case on Windows), and `--provider` reads the instances from T3's `settings.json`, as T3 does: an instance is off when it or its config says `enabled: false`, takes its driver's setting when neither says, and a driver's default instance has the driver's name for its id. Without `--thread`, the current thread is the one T3's `state.sqlite` records for this Claude session, passing over the `import:` row T3 keeps for a session it imported unless that row is the only one. That API is internal to an alpha app and may change between T3 versions. When the script reports an unexpected response, it comes from that API, not from this skill.
