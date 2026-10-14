# dotfiles

Personal, symlink-based setup for a Windows development machine: PowerShell profile, AWS CLI config, and AI coding-agent configuration (Claude Code, Codex, Copilot). Clone it on every machine, run two scripts, and edits made anywhere flow through git. A scheduled task keeps each machine pulled and linked.

## What is managed

| Area | Source in repo | Installed to | Installer |
|---|---|---|---|
| PowerShell profile + helper functions | `powershell/` | `$PROFILE` and the all-hosts profile (symlinks) | `powershell/setup.ps1` |
| AWS CLI profiles (SSO, no secrets) | an overlay's `aws/config` | `%USERPROFILE%\.aws\config` (symlink) | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Git identity | `git/` | `~/.gitconfig` (symlink) | `powershell/setup.ps1` |
| Per-org git identities and other overlay git config | an overlay's `git/gitconfig` | included by `~/.gitconfig-overlays` (generated) | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Agent skills | `ai/skills/<name>/`, here or in an overlay | `~/.claude/skills` and every extra Claude config folder's `skills`, `~/.codex/skills`, `~/.copilot/skills` (symlinks) | `ai/install.sh` |
| Bruno API collections | an overlay's `bruno/<collection>/` | `~/bruno/<collection>` (symlinks) | `ai/install.sh` |
| Claude Code global instructions | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` and each extra Claude config folder's (symlinks) | `ai/install.sh` |
| Claude Code sub-agents | `ai/agents/*.md` | `~/.claude/agents/` and each extra Claude config folder's (symlinks) | `ai/install.sh` |
| Claude Code settings (model, plugins, allowlist) | `ai/claude/settings.json` | merged into `~/.claude/settings.json` and each extra Claude config folder's | `ai/install.sh` |
| Extra Claude config folders, one login each | an overlay's `ai/claude/config-dirs` | the folders it names get the same as `~/.claude` | `ai/install.sh` |
| Skill secrets (encrypted with SOPS + age) | `ai/secrets/<skill>/`, here or in an overlay | `%USERPROFILE%\.agent-secrets\`, then symlinked into every checkout that has the skill (shipped skills read them in place) | `powershell/deploy-secrets.ps1` |
| Commands for every shell, agents' included (`md-lint`, `check-encrypted`) | `bin/` | the user PATH | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Tools and programs a machine needs | `powershell/tools.psd1` | installed via winget, npm, uv and GitHub releases | `powershell/install-tools.ps1` |
| Default markdownlint rules | `powershell/markdownlint.jsonc` | passed to `markdownlint-cli2` by `bin/md-lint` | none (used in place) |
| Automatic pull-and-relink | `powershell/sync.ps1` | Windows scheduled task "Dotfiles Sync" | `powershell/install-sync-task.ps1` |
| Claude account rotation (`cswap auto`), on machines with the `claude-swap` option | none | Windows scheduled task "Claude Swap Auto", at sign-in | `powershell/install-cswap-task.ps1` |
| Copilot repo instructions and prompts | `.github/` | used in place by GitHub Copilot | none |
| Engineering-skill config for this repo | `AGENTS.md`, `docs/agents/` | used in place by Claude Code | none |

## Quick start (new Windows machine)

1. Turn on Developer Mode (Settings > System > For developers) so symlinks work without elevation.
2. Clone the repo anywhere, for example `C:\source\dotfiles`.
3. PowerShell profile and AWS config:

   ```powershell
   cd C:\source\dotfiles\powershell
   .\setup.ps1
   .\install-sync-task.ps1
   ```

   `setup.ps1` links both PowerShell profiles, `~/.aws/config` (when a source exists) and `~/.gitconfig`, writes `~/.gitconfig-overlays`, backs up any real file it displaces, installs everything in [powershell/tools.psd1](powershell/tools.psd1), and offers to reload the profile. `install-sync-task.ps1` registers the "Dotfiles Sync" task (at logon and every 4 hours). Both are safe to re-run.

   `setup.ps1` elevates itself, but **not for the symlinks** — those work unelevated once Developer Mode is on. It elevates so winget installs the manifest machine-wide; unelevated it would quietly fall back to `--scope user`. See [ADR 0002](docs/adr/0002-mklink-not-new-item.md).

   To see what it would do without doing any of it:

   ```powershell
   .\setup.ps1 -Check
   ```

4. AI tooling, from Git Bash:

   ```sh
   ./ai/install.sh
   ./ai/install.sh --check
   ```

5. Private configuration: register the machine as a SOPS recipient in each overlay (see [ai/secrets/README.md](ai/secrets/README.md), "Add a machine"), then add the overlay repo:

   ```powershell
   .\powershell\install-overlays.ps1 -Repo <owner>/<private-repo>
   ```

   It clones the repo beside this one, lists its overlays in `ai\secrets\machine.local.psd1` (created from the example if missing; check its `SearchRoots`), and runs `sync.ps1` to apply them.

## Private configuration: overlays

This repo holds nothing private. Anything that is, such as employer AWS accounts, a work email, or skill secrets whose key names say too much, lives in an **overlay**: a directory in a private repo, laid out like this repo's root. A machine lists its overlays in the git-ignored `ai/secrets/machine.local.psd1`, so no tracked file here names one. One private repo may hold several overlays, one per audience, so an employer's overlay can later move to a repo the employer owns.

What an overlay can supply, and how:

- `ai/secrets/registry.psd1` and `ai/secrets/<skill>/`: merged with every other registry; a skill id may be registered only once.
- `ai/skills/<name>/`: linked beside this repo's skills by `ai/install.sh`, for a skill whose text names something private; a skill name may be shipped from only one place.
- `bruno/<collection>/`: linked into `~/bruno` by `ai/install.sh`, so Bruno opens every overlay's collections from one home; a collection name may be shipped from only one place.
- `ai/claude/config-dirs`: extra Claude config folders, one absolute or `~/…` path per line (`#` starts a comment). `ai/install.sh` gives each the same as `~/.claude`; see [Claude accounts](#claude-accounts).
- `aws/config`: linked to `~/.aws/config`; only one source across this repo and all overlays.
- `git/gitconfig`: included, in overlay order, by the generated `~/.gitconfig-overlays`.

The sync task pulls each overlay repo and re-applies all of these, so a change pushed to an overlay reaches every machine that lists it. Skills are linked by `ai/install.sh`, which the sync runs before it pulls the overlays, so an overlay's skill change lands one sync later. `install-overlays.ps1` is idempotent; re-run it when an overlay repo gains an overlay.

## Claude accounts

Claude Code keeps its login, history and settings in one config folder, `~/.claude` unless `CLAUDE_CONFIG_DIR` names another. Two things here let work run on more than one Claude subscription without signing in and out by hand.

### Route folders: one login per kind of work

A **route folder** is an extra Claude config folder with its own login, for work that should bill a different subscription than `~/.claude` does. Which folders a machine has is private, since a folder's name usually says whose work it is for, so an overlay names them, one per line, in `ai/claude/config-dirs`:

```text
# route folders
~/.claude-client   # client work
```

A line is one absolute path (`/…`, `C:\…` or `C:/…`) or one under the home directory (`~/…` or `~\…`); a path may hold spaces. A `#` at the start of a line, or after a space, starts a comment. A folder named twice, or `~/.claude` itself, is set up once. A path that is neither is skipped with a warning, and `--check` reports it as drift.

`ai/install.sh` makes each one a full Claude home: the same `CLAUDE.md`, agents, skills and managed settings as `~/.claude`, and `--check` reports each folder's links and settings as it does `~/.claude`'s. It never touches a folder's login (`.credentials.json`), `.claude.json`, history or projects. A folder an overlay stops naming is left as it is.

Sign a folder in once, with the account it is for:

```sh
CLAUDE_CONFIG_DIR=~/.claude-client claude auth login
```

**In T3 Code**, the route is chosen per project. Under Settings → Providers, add a Claude provider instance for each route folder and set its "CLAUDE_CONFIG_DIR path" to the folder. Then, in each project that belongs to a route, use the project's provider switch to turn that route's instance on and the default Claude instance off, so no thread in it can start on another account. The switch is a T3 Code server setting, one click per project; nothing here writes it.

Outside T3 Code, a session uses `~/.claude` unless it is started with `CLAUDE_CONFIG_DIR` set.

### claude-swap: several accounts in `~/.claude`

[claude-swap](https://github.com/realiti4/claude-swap) (`cswap`) holds several logins for `~/.claude` and switches between them. `cswap auto` watches the active account's 5-hour and 7-day usage and moves to the account with the most left before the limit is reached; Claude Code picks up the new login on its next message. It is an option: list `claude-swap` under `OptionalTools` in `ai/secrets/machine.local.psd1` and run `dotfiles-tools`, which installs `uv` and then claude-swap with `uv tool install claude-swap`. Then:

1. Sign each account into `~/.claude` in turn (`claude auth login`) and run `cswap add` after each. Do not `/logout` between them: that can revoke the login just added.
2. Run `.\powershell\install-cswap-task.ps1`. It registers the "Claude Swap Auto" scheduled task, which runs `cswap auto` hidden at every sign-in, restarts it a minute after it exits, logs to `%LOCALAPPDATA%\dotfiles\cswap-auto.log`, and starts it now. Re-running it is safe; `-Uninstall` stops and removes it.
3. `cswap list` shows every account's usage and which one is active.

claude.ai connectors (Atlassian, Microsoft 365 and the like) belong to a claude.ai account, not to a machine, so after a switch new sessions get the other account's connectors. Set up the connectors you need on every account in the rotation.

claude-swap rotates `~/.claude` only. A route folder with one account needs no rotation.

## Keeping machines in sync

- Edit files in this repo, commit, push.
- Other machines pull and re-link automatically via the scheduled task, or on demand with `dotfiles-sync` in PowerShell. Symlinked files pick up edits without re-running anything; new files need a re-link, which the sync does.
- Every installer has a report-only mode that changes nothing and exits non-zero if anything is out of sync: `./ai/install.sh --check`, `.\powershell\setup.ps1 -Check`, `.\powershell\deploy-secrets.ps1 -Check` and `dotfiles-tools -Check`. Each reports links that are missing, replaced by a real file, or pointing elsewhere. They answer "is this machine in sync with the repo?" — not "is this code correct?", which is what `tests/` is for.
- Tools are declared in [powershell/tools.psd1](powershell/tools.psd1). Add an entry, commit, push, and every machine installs it on its next sync — the sync only does this work when the manifest, or the machine's options, have actually changed. Entries marked `Unattended = $false` are skipped by the scheduled task and wait for `dotfiles-tools`; `dotfiles-tools -Check` reports what is missing without installing anything.
- Optional tools install only on machines that ask for them. An entry with `Optional = 'openwhispr'` belongs to that option; list the name under `OptionalTools` in `ai/secrets/machine.local.psd1` and run `dotfiles-tools` to install it, its first-run step included. Machines that don't list it are told it is available. A machine without skill secrets can write that file just for `OptionalTools`: the sync deploys secrets only when it also declares `SearchRoots`.

## Layout

- [powershell/](powershell/README.md): profile, setup, sync, AWS, Git and rig helper functions
- [aws/](aws/README.md): how the AWS CLI config is supplied
- [ai/](ai/README.md): agent skills, Claude Code config, installer
- [.github/](.github/instructions/README.md): Copilot instructions and reusable prompts
- [tests/](tests/README.md): fixture tests for the parts that can be tested without touching the machine you are on; CI runs them on every pull request
- [GLOSSARY.md](GLOSSARY.md): the glossary — what "managed", "drift", "checkout" and the rest mean here
- [docs/adr/](docs/adr/): the decisions a reader would otherwise try to undo, and why
- [docs/agents/](docs/agents/): issue tracker, triage labels and domain-doc conventions read by the engineering skills
- [RELEASES.md](RELEASES.md): change log
