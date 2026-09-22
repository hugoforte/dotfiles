# AI tooling

Configuration for AI coding agents (Claude Code, Codex, Copilot). Everything is installed by symlink, so a `git pull` updates the live config. `powershell/sync.ps1` does the pull and re-link, on a schedule or via `dotfiles-sync`.

## What is in here

| Path | What it is |
|---|---|
| `skills/<name>/` | Agent skills. Each folder has a `SKILL.md`. Linked into every tool's skills directory. |
| `CLAUDE.md` | Global Claude Code instructions, linked to `~/.claude/CLAUDE.md`. |
| `agents/*.md` | Claude Code sub-agents: `implementation-planner`, `code-reviewer`, `unit-test-writer`, `bug-root-cause-analyzer`, `note-taker`, `prompt-optimizer`, `task-orchestrator`. Referenced from `CLAUDE.md`. |
| `claude/settings.json` | Fragment merged into `~/.claude/settings.json`: model, plugins, marketplaces, UI prefs, a read-only tool allowlist. |
| `install.sh` | Installer, checker and uninstaller for all of the above. |
| `validate-settings.sh` | Prints a summary of `~/.claude/settings.json` (needs `jq`). |
| `helpers/` | `output.sh` (colored output, same prefixes as `powershell/output.ps1`) and `settings-reconcile.sh` (the managed-key spec, and the merge, check and export directions over it). |
| `licenses/` | License and pinned version for vendored third-party skills. |
| `secrets/` | Encrypted credential files for project-level skills, deployed by `powershell/deploy-secrets.ps1`. See [secrets/README.md](secrets/README.md). |

## Installing

From Git Bash on Windows, or any POSIX shell:

```sh
./ai/install.sh              # install everything
./ai/install.sh --check      # report drift, change nothing (exit 1 on drift)
./ai/install.sh --uninstall  # remove the symlinks
./ai/install.sh --help       # component flags: --skills-only, --no-settings, ...
```

| Component | Source | Target | Needs |
|---|---|---|---|
| `CLAUDE.md` | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` | symlinks |
| Agents | `ai/agents/*.md` | `~/.claude/agents/` | symlinks |
| Skills | `ai/skills/*/` | `~/.claude/skills/`, `~/.codex/skills/`, `~/.copilot/skills/` (the last two only when the tool dir exists) | symlinks |
| Settings | `ai/claude/settings.json` | merged into `~/.claude/settings.json`, backup taken first | `jq` (`winget install jqlang.jq`) |

Symlinks on Windows need Developer Mode (Settings > System > For developers) or an elevated shell. On Git Bash the script sets `MSYS=winsymlinks:nativestrict` so `ln -s` makes real symlinks instead of silently copying.

An existing real file or directory at a target path is never overwritten; the script warns and skips it. Delete the local copy and re-run to let the repo own it.

A skill or agent deleted from the repo leaves a dangling symlink on every machine that had it linked, which the agents still list and then fail to read. An install prunes those, and `--check` reports them as drift. Only links pointing into this repo are touched.

## Skills

### Managed here

| Prefix | Count | Origin |
|---|---|---|
| `matt-*` | 24 | [mattpocock/skills](https://github.com/mattpocock/skills), engineering + productivity sets, MIT. Pinned commit in `licenses/mattpocock-skills-VERSION`. |
| `hf-*` | 5 | Own. One per row below. |

My own skills carry an `hf-` prefix, so a skill list says at a glance which ones this repo wrote and which came from somewhere else.

| Skill | What it does |
|---|---|
| `hf-adversarial-review` | Sets a subagent on a PR to find what is wrong with it, verifies the findings, fixes the real ones and pushes. Takes a rig work's PRs, or a single PR outside one. |
| `hf-assign-devs-to-pr` | Asks which of the team should take a PR, then requests their review and assigns them via `gh`. Holds the roster of names and GitHub handles. |
| `hf-resolve-pr-comments` | Works a PR's review comments to zero: action, reply, resolve. |
| `hf-dotfiles-secrets` | The procedures for the encrypted skill secrets under `secrets/`. |
| `hf-rig` | Finds the [rig](https://github.com/hugoforte/rig) cross-repo work harness and routes into it: how to invoke it from any shell, `rig doctor` for everything machine-specific, and which rig command answers which request. |

Matt's skills are prefixed `matt-` (folder and `name:`), and their `/slash` cross-references were rewritten to match, so `/matt-triage`, `/matt-grill-with-docs`, and so on. Backticked mentions like "the `research` skill" were left as-is because the same words also name wayfinder ticket types.

### Adding a skill

1. Put the folder under `ai/skills/<name>/` with a `SKILL.md` whose `name:` matches the folder. Own skills take an `hf-` prefix.
2. `./ai/install.sh --skills-only`
3. Commit and push. Other machines pick it up on their next sync.

To adopt a skill that already lives in `~/.claude/skills/<name>`: move the folder into `ai/skills/` and run the installer.

### Updating Matt's skills

```sh
git clone --depth 1 https://github.com/mattpocock/skills /tmp/mattskills
```

Copy the wanted folders from `skills/engineering` and `skills/productivity` to `ai/skills/matt-<name>`, set `name: matt-<name>` in each `SKILL.md`, rewrite `/<name>` references to `/matt-<name>`, and update `licenses/mattpocock-skills-VERSION`. Skills in `in-progress`, `misc` and `deprecated` were deliberately not vendored.

### Not managed here

- `twg` skills: installed by the TWG CLI installer next to its binary; per machine.
- Work skills that live in an app repo (`app-db-query`, `payments-query`, `payment-vendor-sandbox`): the skill stays there; only its credential files are managed here, under `secrets/`.

## Settings

`claude/settings.json` is the fragment. `helpers/settings-reconcile.sh` moves keys between it and `~/.claude/settings.json` in three directions — merge, check and export — over one spec of what "managed" means: a managed key is a leaf path of the fragment, where arrays count as leaves and objects do not. Nothing outside that set is read or written in any direction, so the live file keeps its machine-local or secret-bearing keys and the committed fragment never acquires them.

Both write directions union arrays and neither deletes, so:

- `./ai/install.sh --check` compares every managed key in both directions. `MISSING` (a key, or an array entry, that the fragment declares and the live file lacks) and `DIFF` (a scalar changed on the Claude side, e.g. via `/model`) count as drift. `EXTRA` lists live-only array entries, such as "always allow" answers, and is informational.
- `./ai/install.sh --settings-export` copies the managed leaf paths from the live file back into the repo fragment — live scalars win, arrays union — and leaves every unmanaged key, such as `permissions.deny`, where it is. Review with `git diff`, then commit. This is how a change made through Claude reaches other machines.
- To remove an allowlist entry everywhere, delete it from the fragment and from each machine's live file; no direction deletes.

## Agents and CLAUDE.md

`CLAUDE.md` names the seven agents and when to use them. Agents write plans, notes and reviews under `~/ai-notes/`. Both are plain markdown; edit in the repo and the symlink makes it live.
