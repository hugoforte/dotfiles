---
name: hf-t3-handoff
description: Hand the current T3 Code thread over to a fresh one — write the handoff, start a new thread titled with the next number that runs it, and archive this one. The new thread starts on this computer, in this project and on this provider instance, unless another is named. Use when asked to hand off, continue in a new thread, continue on another computer, in another project or on another provider instance, or start over with a clean context inside T3 Code.
argument-hint: "What will the next session be used for? Name another computer, project folder or provider instance to continue there."
disable-model-invocation: true
---

# T3 handoff

A handoff, then a new T3 Code thread that picks it up, then this thread archived. The new thread gets this thread's project, branch or worktree, model, provider instance, and access mode, unless the user names another project or provider instance.

On this computer you do it with T3's `t3-code` MCP tools; `t3.mjs` gives you the titles. Their names may carry a prefix, such as `mcp__t3-code__t3_thread_launch`; load them with your tool search when they are deferred.

The new thread starts on this computer. It starts on another one only when the user names it, in the arguments or earlier in the conversation ("hand off to the laptop"). Never pick another computer yourself. The MCP tools reach only this computer's T3 Code, so the new thread there is started by `t3.mjs` with `--to <computer>`, in the checkout of that computer's T3 project for the same repository, since a branch or worktree of this computer means nothing there.

The same goes for another project or another provider instance on this computer, such as a thread started in the wrong project or under the wrong Claude account: only when the user names them. In another project the thread starts in that project's checkout, since this thread's branch or worktree belongs to this one. On another instance it keeps the model and its options. Neither goes with another computer.

Threads of a rig work are titled `RIG - [KEY] Short description`, and each handoff counts up: `… Short description 1`, then `… 2`. A thread whose title is not in that form yet is renamed to it before it is archived.

## What it needs

- **rig**, set up, with its `rig-handoff` skill linked into `~/.claude/skills`.
- **T3 Code** with its `t3-code` MCP server, running this skill from a thread in it: `t3_thread_configuration`, `t3_thread_read`, `t3_thread_launch`, `t3_thread_update` and `t3_thread_organize`, and `t3_project_list` or `orchestrator_capabilities` for another project or provider instance.
- **Node 22 or later** for `t3.mjs`.
- **For another computer**: T3 Code running there with its server network-accessible, the repository added as a project in it, and that computer's entry in `~/.agent-secrets/hf-t3-handoff/computers.local.json` on this one. That file is a skill secret: `deploy-secrets.ps1` decrypts it from `ai/secrets/hf-t3-handoff/` in the personal overlay, so one copy lists every machine and reaches each of them by sync. Running `node ~/.claude/skills/hf-t3-handoff/t3.mjs token` on a computer prints its entry, token included, and the entry goes into the overlay's file with `sops edit` (see the `hf-dotfiles-secrets` skill), never into the decrypted copy. That is the user's to run and to paste: the token is a password, so never ask for it in chat and never print the file.

## 0. Check the setup

Call `t3_thread_configuration` with no arguments. It answers with this thread's id, model selection and modes; keep the answer. If the tool is not there, or fails, tell the user this skill needs T3 Code's `t3-code` MCP server and stop.

For another computer, also call `t3_project_read` with the `projectId` from `t3_thread_read` on this thread, and write a JSON file in the OS temp directory: `{ "project": <t3_project_read's answer>, "configuration": <t3_thread_configuration's answer> }`, each answer as the tool gave it. That file is the `--from` below.

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs check [--to <computer> --from <file>]
```

It checks each requirement and prints `ok` or `FAIL`. Every failure comes with the command or step that fixes it. If any line fails, show the user the output as it is, offer to run the fixes that are commands, and stop: nothing has been committed or written yet. Do not start the handoff with a requirement missing, because a handoff that cannot open its new thread leaves the user to paste the prompt by hand.

## 1. Write the handoff

Follow the `rig-handoff` skill: read `~/.claude/skills/rig-handoff/SKILL.md` and do all of it, with this skill's arguments as the next session's focus. It covers both cases, inside a rig work and outside one, and it stops for the user where it says to. If it stopped, stop here too.

It ends with a prompt for a fresh session. That prompt is what the new thread receives, exactly as it is and without the code fence. For another computer, write it to a file in the OS temp directory.

For another computer, the prompt must hold on a machine that has none of this one's files. Inside a rig work it already does: the branches are pushed and the prompt reads the handoff from the data root's remote. Outside one, nothing has left this machine, so before going on:

- Push the branch the work is on, and name it in the prompt as the branch to check out. Commit only tracked changes and ask the user first; if they would rather not push, stop.
- Put the handoff's whole text in the prompt in place of the path to it, which is a temp file only this computer has.

## 2. Name the new thread

Call `t3_thread_read` with this thread's id, `limit` 1. Keep its `title`, `projectId`, `branch` and `worktreePath`. If it says `archived`, stop: the thread was already handed off.

Inside a rig work, take the title's parts from `rig status`:

- **Key**: the first entry on its `tickets` line. A GitHub issue (`owner/repo#N`) is written as `repo#N`. A work with no ticket uses its id, the first word of `rig status`.
- **Description**: the work's title, cut to about five words, leading with the product when the work is about one (`IM unable to add product`). It must not end in a number, because a trailing number is read as the count.

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs title --current "<this thread's title>" [--key <key> --description "<description>"]
```

It prints `{"rename":"…","next":"…"}`; `rename` is there only when this thread needs renaming. When the title is already standard, it keeps its key and description and ignores the two flags. Outside a rig work, leave both out: the title then counts up as it is, so "Foo" becomes "Foo 2".

## 3. Start the new thread

### On this computer

Work out the launch, then say it to the user in one line: the new title, where it starts, the model and, with another instance, the instance's display name, any rename, and that this thread will be archived. If any of it looks wrong, stop and tell the user.

- **Where**: in this thread's worktree, `workspaceStrategy` `{"type":"existing_worktree","worktreePath":<worktreePath>,"branch":<branch>}`; with no worktree, `{"type":"root","branch":<branch>}`, leaving `branch` out when it is null. Always pass one: an omitted strategy means the project's checkout, not this thread's worktree.
- **Another project**, named by its folder: `t3_project_list`, and the one project whose `workspaceRoot` is that folder, compared as absolute paths with either slash, without a trailing one, and without case on Windows. None, or several, is a stop: tell the user to add the folder as a project in T3 Code, or to remove all but one. For this thread's own project, keep the strategy above. For another, pass its `projectId` and `{"type":"root"}`.
- **Another provider instance**: `orchestrator_capabilities`, and the instance whose `providerInstanceId` or `displayName` the user named. It must have no "disabled" constraint and the same `driverKind` as this thread's instance, since the model belongs to its driver; otherwise stop and list the enabled instances of that driver with their display names. Pass `modelSelection` as this thread's, with only `instanceId` changed.
- Leave the model and the modes out otherwise: the new thread inherits them from this one.

Then call `t3_thread_launch` with `title` the next title, `message` the prompt, the `workspaceStrategy`, and `projectId` and `modelSelection` only when they changed. Keep the `threadId` it returns. It takes no retry key: if it fails, or its answer is lost, look for the thread with `t3_thread_list` (`titleContains` the next title) before anything else, and never launch again while it may exist.

Call `t3_thread_read` on the new thread, `limit` 1, until `recentRuns[0].status` is `running`, `waiting` or `completed`, for up to a minute. A run still `preparing`, `queued` or `starting` has not started yet; one `failed`, `cancelled`, `interrupted` or `rolled_back` stops the handoff, with this thread left open. If it has not started after a minute, stop and tell the user: it may still start, as when a setup script is slow, and this thread stays open.

### On another computer

```bash
node ~/.claude/skills/hf-t3-handoff/t3.mjs continue --to <computer> --from <file> --title "<next title>" --prompt-file <file> --dry-run
```

The dry run names the thread it would start, the computer and the project folder there, and the model. If any of it looks wrong, stop and tell the user. If the dry run is right, run the same command without `--dry-run`. It launches the thread there and waits for its run to start, then prints `Started …`. If it fails, it prints the problem and its fix the same way `check` does, and says whether the new thread may exist: never run it again until the user has looked for it in T3 Code on that computer.

## 4. Report, then close this thread

Archiving this thread may stop this session at once, so the report comes first. In one or two lines: the new thread's title as a link, `[title](t3-thread://v1/<threadId>)` with the id as `t3_thread_launch` returned it (a thread on another computer by its title and the computer instead), and where the handoff was saved. If anything failed, quote the error and say whether the new thread may exist.

Then, only once the new thread's run has started:

1. When `title` printed a `rename`, `t3_thread_update` with `action` `rename` and that title, leaving `threadId` out.
2. `t3_thread_organize` with `action` `archive`, leaving `threadId` out. This is the last call.

If either fails, the new thread is running and this one needs renaming and archiving by hand in T3 Code: say so, and do not start the handoff again.

## How it works

On this computer every step is an MCP tool of T3 Code's own: the launch creates the thread in its workspace and starts it with the prompt, and the new thread inherits the model, its options and the modes unless `modelSelection` says otherwise.

`t3.mjs` holds the title rule, `handoffTitles`, and the path to another computer. There it drives the other computer's T3 Code server through the API T3's own client uses, orchestration protocol 2, with the origin and token its entry in `computers.local.json` gives. It reads that server's projects over HTTP with the `x-t3-orchestration-protocol: 2` header, picks the project whose repository matches this thread's project, and gives one `orchestration.launchThread` over T3's WebSocket RPC at `/ws`, in that project's checkout, with the model selection and modes from `--from`. T3 says a project's repository only once it has looked its remote up, and forgets it a minute later, so the script reads the other computer's projects again for a moment while any lacks one, and takes this project's from its checkout's `upstream` or `origin` when T3 has not said it. That API is internal to a pre-1.0 app and may change between T3 versions. A server on another protocol answers 400 or 426, and the script names that server's origin and says to update T3 Code there. When the script reports an unexpected response, it comes from that API, not from this skill. `token` mints the entry's token with T3's `auth session issue` CLI, through the launcher the app writes to `~/.t3/bin/t3` (`t3.cmd` on Windows), or `T3CODE_CLI_PATH`, scoped to reading and commanding threads.
