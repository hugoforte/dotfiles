---
name: rig
description: Cross-repo work harness. Use when a ticket or task spans more than one repo, when asked to set up worktrees for a piece of work, when working inside a `D:\w\<work>` folder, or when asked what work is open or to close one.
---

`rig` assembles one git worktree per repo for a piece of **work**, all on one shared branch, and keeps that work's durable context in a **data root** — a committed checkout holding the catalogue, the work records and `rig.json`; a private repo when the tool itself is public. Full instructions live with the tool; this skill gets you there from anywhere.

## Step 1: Locate rig

The checkout is at `RIG_ROOT` if set, else `D:\rig`, else `C:\rig`. Confirm with `ls <root>/bin/rig.mjs`.

Invoke it as `node <root>/bin/rig.mjs <command>` in every shell. The bare `rig` command is a PowerShell profile function and is absent from Git Bash, which is what Claude Code's Bash tool runs.

**No checkout anywhere:** install it, then continue. Needs Node 18+, `git`, and an authenticated `gh` (the repo is private).

```powershell
rig-install [-Path <dir>] [-Email <work address>] [-DataRepo owner/rig-data]   # dotfiles profile function: clone + init
```

Or the commands it wraps, from any shell: `gh repo clone hugoforte/rig <path>`, optionally `gh repo clone <owner>/rig-data <path>\..\rig-data`, then `node <path>/bin/rig.mjs init --email <work address> [--data-root <data path>]`. Ask the user for the path, the email and whether there is a data repo rather than guessing; the defaults are `D:\rig` and an empty identity. The data root must be a checkout of its own beside the tool, never the tool checkout — rig refuses to commit knowledge into that.

**Installed but `rig doctor` says "not set up":** there is no `rig.json` with orgs in the data root. Run `node <root>/bin/rig.mjs prompt setup` and follow it — it ends in one `rig init` with `--orgs` and `--tracker`.

## Step 2: Read the instructions

Read `<root>/AGENTS.md` in full. It is the single source of truth for how rig works: the three roots (the tool, the data root, and disposable `D:\w`), the commands, the catalogue, the context-doc conventions, and the rules. Continue only once you have read it.

`node <root>/bin/rig.mjs help` lists the commands with their flags.

## Step 3: Pick the branch

**New work** (a ticket key in `$ARGUMENTS`, or a request to start on something):

1. **Decide the ticket before `rig new`, with the user.** `rig new` refuses on any data root with a tracker unless you pass `--key`, `--ticket` or `--no-ticket`; the decision is never left implicit. Run `node <root>/bin/rig.mjs prompt new-work` and follow it:
   - A Jira key given (`PROJ-42`): `rig new <id> --key PROJ-42`. rig fetches the summary and description itself via `twg`; only a GitHub key still needs its brief piped in.
   - No key: **ask whether to create a ticket**. If yes, `rig new <id> --title "…" --ticket --org <org> --dry-run` prints what would be created (for Jira: project, type, and every field, sprint and components resolved), present that and **stop** for confirmation, then run it again without `--dry-run`, with `--field name=value,…` for anything the user changed. Only on an explicit no: `--no-ticket`, which records the decision.
2. Run `node <root>/bin/rig.mjs prompt select-repos` and follow it. It ends by presenting a repo set and **stopping for confirmation**; attach repos only after the user confirms.
3. Once the Direction section of the context doc is agreed with the user, end that gate with `node <root>/bin/rig.mjs save -m "design agreed" --designed`. rig commits and pushes the data root after its own commands; the context doc is yours to edit, so this is how those edits get committed (`rig save -m "…"` for any later one).

**Existing work**: `cd D:\w\<work-id>`. The generated `AGENTS.md` there names the repos, their roles, the branch, and the path to the context doc. Commands that act on the current work resolve it from that folder.

**Status or teardown**: `node <root>/bin/rig.mjs list` shows every work and which are safe to close; `close` refuses while anything is uncommitted, unpushed, or has an open PR.

## Rules that survive from `AGENTS.md`

- Inside `D:\w`, repos are added with `rig attach`; rig owns that tree and `rig doctor` fails on anything else. Elsewhere, `git worktree add` is fine and rig ignores it.
- Prose goes in `<data root>\work\<id>\context.md`, the only copy (`rig doctor` prints the data root; on this machine it is `D:\rig-data`). Every `AGENTS.md` under `D:\w` is generated and regenerated; edits there are lost.
- Branch, base, ahead/behind and PR state come from `rig status`, never from a doc. The one recorded state is `status` (planning, in-progress, designed, closed), set by rig at each gate.
- Every rig command that changes a work commits the whole data root and pushes it; nothing asks first and nothing runs on a timer. Edits you make by hand in the data root wait for `rig save`.
- On `rig close`, every ticket gets a comment with the PR links; GitHub tickets also close when every PR is merged. Jira tickets are never transitioned by rig — that is yours.
