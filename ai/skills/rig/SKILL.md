---
name: rig
description: Cross-repo work harness. Use when a ticket or task spans more than one repo, when asked to set up worktrees for a piece of work, when working inside a `D:\w\<work>` folder, or when asked what work is open or to close one.
---

`rig` assembles one git worktree per repo for a piece of **work**, all on one shared branch, and keeps that work's durable context in its own repo. Full instructions live with the tool; this skill gets you there from anywhere.

## Step 1: Locate rig

The checkout is at `RIG_ROOT` if set, else `D:\rig`, else `C:\rig`. Confirm with `ls <root>/bin/rig.mjs`.

Invoke it as `node <root>/bin/rig.mjs <command>` in every shell. The bare `rig` command is a PowerShell profile function and is absent from Git Bash, which is what Claude Code's Bash tool runs.

**No checkout anywhere:** install it, then continue. Needs Node 18+, `git`, and an authenticated `gh` (the repo is private).

```powershell
rig-install [-Path <dir>] [-Email <work address>]     # dotfiles profile function: clone + init
```

Or the two commands it wraps, from any shell: `gh repo clone hugoforte/rig <path>` then `node <path>/bin/rig.mjs init --email <work address>`. Ask the user for the path and email rather than guessing; the defaults are `D:\rig` and an empty identity.

## Step 2: Read the instructions

Read `<root>/AGENTS.md` in full. It is the single source of truth for how rig works: the two roots (`D:\rig` durable and committed, `D:\w` disposable), the commands, the catalogue, the context-doc conventions, and the rules. Continue only once you have read it.

`node <root>/bin/rig.mjs help` lists the commands with their flags.

## Step 3: Pick the branch

**New work** (a ticket key in `$ARGUMENTS`, or a request to start on something):

1. Fetch the ticket text yourself with whatever Jira tooling you have and pipe it into `rig new` as the brief. rig authenticates to nothing but git.
2. Run `node <root>/bin/rig.mjs prompt select-repos` and follow it. It ends by presenting a repo set and **stopping for confirmation**; attach repos only after the user confirms.

**Existing work**: `cd D:\w\<work-id>`. The generated `AGENTS.md` there names the repos, their roles, the branch, and the path to the context doc. Commands that act on the current work resolve it from that folder.

**Status or teardown**: `node <root>/bin/rig.mjs list` shows every work and which are safe to close; `close` refuses while anything is uncommitted, unpushed, or has an open PR.

## Rules that survive from `AGENTS.md`

- Inside `D:\w`, repos are added with `rig attach`; rig owns that tree and `rig doctor` fails on anything else. Elsewhere, `git worktree add` is fine and rig ignores it.
- Prose goes in `D:\rig\work\<id>\context.md`, the only copy. Every `AGENTS.md` under `D:\w` is generated and regenerated; edits there are lost.
- Branch, base, ahead/behind and PR state come from `rig status`, never from a doc.
