# AI tooling

Configuration for AI coding agents. Everything here is installed by symlink, so a `git pull` updates the live config.

## What is in here

| Path | What it is | Status |
|---|---|---|
| `skills/<name>/` | Agent skills managed by this repo. Each folder has a `SKILL.md`. | In use. Currently: `excalidraw-diagram`, vendored from [coleam00/excalidraw-diagram-skill](https://github.com/coleam00/excalidraw-diagram-skill) |
| `install.sh` | Installer. Links skills, `CLAUDE.md` and agents; registers MCP servers; writes hooks and permissions. | In use for skills; other components inherited, see below |
| `CLAUDE.md` | Global Claude Code instructions, linked to `~/.claude/CLAUDE.md` | Inherited from upstream, not yet adapted |
| `agents/*.md` | Claude Code sub-agents: planner, reviewer, test writer, root-cause analyzer, note taker, prompt optimizer, task orchestrator, support | Inherited from upstream, partly PostHog-specific |
| `configure-tool-permissions.sh` | Writes an allow/deny list into `~/.claude/settings.json` | Inherited from upstream |
| `validate-settings.sh` | Sanity-checks `~/.claude/settings.json` (needs `jq`) | Works |
| `helpers/` | `output.sh` (colored output) and `json-settings.sh` (merge JSON into settings) | Works |

## Installing

Run from Git Bash on Windows, or any POSIX shell elsewhere:

```sh
./ai/install.sh --skills-only     # recommended today
./ai/install.sh                   # everything
./ai/install.sh --help            # all flags
```

| Component | Install alone | Skip | Needs |
|---|---|---|---|
| Skills | `--skills-only` | `--no-skills` | Windows Developer Mode or an elevated shell (native symlinks) |
| `CLAUDE.md` | `--claude-md-only` | `--no-claude-md` | same |
| Agents | `--agents-only` | `--no-agents` | same |
| MCP servers | `--mcp-only` | `--no-mcp` | `claude`, `npx` |
| Hooks | `--hooks-only` | `--no-hooks` | `jq` |
| Permissions | `--permissions-only` | `--no-permissions` | `jq` |

`--uninstall` removes the symlinks created by the file-based components. It never removes MCP servers, hooks or permissions.

On Git Bash the script sets `MSYS=winsymlinks:nativestrict` so `ln -s` creates real Windows symlinks instead of silently copying. Without Developer Mode or elevation the link step fails with a permission error.

## Skills

### How syncing works

Every `ai/skills/<name>/` directory is linked as `<tool>/skills/<name>` into:

- `~/.claude/skills` (always)
- `~/.codex/skills` (when `~/.codex` exists)
- `~/.copilot/skills` (when `~/.copilot` exists)

An existing real directory with the same name is left alone with a warning. Delete the local copy and re-run to let the repo own it.

### Adding a skill

1. Put the skill folder under `ai/skills/<name>/` with a `SKILL.md` whose `name:` matches the folder.
2. Run `./ai/install.sh --skills-only`.
3. Commit and push. On other machines: `git pull` and re-run the same command.

To adopt a skill that already lives in `~/.claude/skills/<name>`: move the folder into `ai/skills/`, then run the installer.

### Skills not managed here

Third-party skill sets installed directly into the tool directories are not synced by this repo and must be reinstalled per machine:

- [mattpocock/skills](https://github.com/mattpocock/skills): triage, to-spec, tdd, grilling and friends
- `twg` skills, installed by the TWG CLI installer alongside its binary
- Work-specific skills that carry credentials

## Inherited from upstream

This folder was forked from haacked/dotfiles and these parts still reflect that author's setup. Treat them as templates until rewritten:

- `CLAUDE.md`: PostHog architecture notes, `haacked/<slug>` branch naming, `~/dev/...` paths, worktree workflow
- `agents/code-reviewer.md`, `agents/note-taker.md`, `agents/support-hero-logger.md`: PostHog and Zendesk specifics
- `install.sh` MCP list: `posthog-db` and `spelungit` point at paths that do not exist here
- `configure-tool-permissions.sh`: PostHog MCP tool names and a `Read(//Users/haacked/dev/**)` rule

Running `./ai/install.sh` without flags applies all of this. Use `--skills-only` until the rest is reviewed.
