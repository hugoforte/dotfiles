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
| `helpers/` | `output.sh` (colored output) and `json-settings.sh` (deep-merge JSON into a settings file). |
| `licenses/` | License and pinned version for vendored third-party skills. |

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

## Skills

### Managed here

| Prefix | Count | Origin |
|---|---|---|
| `matt-*` | 25 | [mattpocock/skills](https://github.com/mattpocock/skills), engineering + productivity sets, MIT. Pinned commit in `licenses/mattpocock-skills-VERSION`. |
| `review-pr` | 1 | Own. PR review workflow via `gh`. |
| `excalidraw-diagram` | 1 | [coleam00/excalidraw-diagram-skill](https://github.com/coleam00/excalidraw-diagram-skill). |

Matt's skills are prefixed `matt-` (folder and `name:`), and their `/slash` cross-references were rewritten to match, so `/matt-triage`, `/matt-grill-with-docs`, and so on. Backticked mentions like "the `research` skill" were left as-is because the same words also name wayfinder ticket types.

### Adding a skill

1. Put the folder under `ai/skills/<name>/` with a `SKILL.md` whose `name:` matches the folder.
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
- Work skills that carry credentials: see the agent-secret-sync issue in this repo.

## Settings

`claude/settings.json` is deep-merged into `~/.claude/settings.json`: objects merge, arrays union, scalars in the fragment win. Machine-local keys already in the target survive. Grow the `permissions.allow` list here rather than in the live file so it syncs.

## Agents and CLAUDE.md

`CLAUDE.md` names the seven agents and when to use them. Agents write plans, notes and reviews under `~/ai-notes/`. Both are plain markdown; edit in the repo and the symlink makes it live.
