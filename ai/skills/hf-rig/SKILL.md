---
name: hf-rig
description: Cross-repo work harness. Use when a ticket or task spans more than one repo, when asked to set up worktrees for a piece of work, when standing in a rig work folder, or when asked what work is open or to close one.
---

# rig

`rig` assembles one git worktree per repo for a piece of **work**, all on one shared branch, and keeps that work's durable knowledge in a **data root** — a committed checkout holding the repo catalogue, the work records and `rig.json`.

rig documents itself, and that documentation ships with the tool. This skill finds rig and routes you inside it. It restates none of it on purpose: a restatement here rots on rig's release cadence rather than this repo's, and every fact this skill ever got wrong was one it had copied.

## Step 1: Find rig

`rig <command>` works in every shell on a set-up machine. In Git Bash it is an npm global shim; in PowerShell it is a profile function from `powershell/rig.ps1`. Both reach the same checkout — the npm global is a symlink to it — so one `rig update` moves both.

Confirm with `command -v rig`. If it is missing, the checkout is at `RIG_ROOT`, else `C:\rig`, else `D:\rig`, and `node <root>/bin/rig.mjs <command>` runs it from there.

**No checkout at all:** `rig-install [-Path <dir>] [-Email <work address>] [-DataRepo owner/rig-data]`, a profile function from this repo — `powershell/README.md` has its arguments. It needs Node 18+, `git`, and an authenticated `gh`. Ask for the path, the work email and whether there is a data repo; do not guess. Everything after the clone is `rig prompt setup`'s to ask.

## Step 2: Orient

```bash
rig doctor
```

One command, and the only place to learn any of it: the version and record format, the work root, every data root this machine knows with its tracker and identity, and every finding. Read it before acting. Nothing about this machine's layout is written into this skill, because the answer differs per machine and `doctor` always has the current one.

`doctor` saying **not set up** means there is no data root with a `rig.json`. Run `rig prompt setup`.

## Step 3: Read the instructions

Read `<root>/AGENTS.md` in full. It is the single source of truth for how rig works — the three roots, the commands, the catalogue, the context doc, the rules. Continue only once you have read it. `rig help` lists every command with its flags.

## Step 4: Route

| The request | Start here |
|---|---|
| Start a piece of work | `rig prompt new-work`, then `rig prompt select-repos` |
| Which repos does it touch | `rig prompt select-repos` |
| First run on this machine | `rig prompt setup` |
| Standing in a work, what now | `rig next` |
| Where has this work got to | `rig status` |
| What is open, what can close | `rig list` |
| Slice the work into reviewable parts | `rig stage` |
| Put it up for review | `rig pr` |
| Deploy order, rollout, UAT | `rig plan`, `rig plan --refresh` |
| How is a repo verified | `rig check [--run]` |
| Context doc edited by hand | `rig save -m "…"` |
| Design agreed with the user | `rig save -m "design agreed" --designed` |
| Finished | `rig close` |
| Stopped without finishing | `rig close --abandoned` |
| A command died with "run `rig update`" | `rig update`, from the installed checkout |
| Whose knowledge is in hand | `rig use` |

**Stop for the user at three points**, and `rig new` enforces the first by refusing without it: the ticket decision (`--key`, `--ticket` or `--no-ticket`), the repo set, and the design gate. Each `rig prompt` ends by stopping; do not run past it.

**More than one data root is normal** — personal, public and employer knowledge have different readers. A work lives in exactly one, and `rig new --repos a,b` refuses repos catalogued in different roots. `rig use` says which is in hand.

## Two rules before you have read `AGENTS.md`

- **Never `git worktree add` inside the work root.** `rig attach` adds repos; rig owns that tree and `rig doctor` fails on strays. Outside it, do as you like.
- **Never edit a generated file.** Every `AGENTS.md` under the work root is rewritten on each mutating command, as is `demo/index.html`. Prose lives in the work's `context.md`, which is the only copy.
