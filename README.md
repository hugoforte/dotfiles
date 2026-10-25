# dotfiles

Personal, symlink-based setup for Windows and macOS development machines: shell profile, git and AWS CLI config, tools, and AI coding-agent configuration (Claude Code, Codex, Copilot). Clone it on every machine, run its setup, and edits made anywhere flow through git. A scheduled task keeps each Windows machine pulled and linked. Windows is set up by `powershell/`, a Mac by `macos/` ([ADR 0007](docs/adr/0007-a-parallel-macos-entry-point.md)).

## What is managed

| Area | Source in repo | Installed to | Installer |
|---|---|---|---|
| PowerShell profile + helper functions | `powershell/` | `$PROFILE` and the all-hosts profile (symlinks) | `powershell/setup.ps1` |
| AWS CLI profiles (SSO, no secrets) | each overlay's `aws/config` | `%USERPROFILE%\.aws\config`, `~/.aws/config` on a Mac (generated: every source merged) | `powershell/setup.ps1`, `powershell/sync.ps1`, `macos/setup.sh` |
| The SSH keys that may log in | an overlay's `ssh/authorized_keys` | `~/.ssh/authorized_keys`: a copy on Windows, a symlink on a Mac | `powershell/setup.ps1`, `powershell/sync.ps1`, `macos/setup.sh` |
| Git identity | `git/`, and `macos/gitconfig` on a Mac | `~/.gitconfig` (symlink) | `powershell/setup.ps1`, `macos/setup.sh` |
| Per-org git identities and other overlay git config | an overlay's `git/gitconfig` | included by `~/.gitconfig-overlays` (generated) | `powershell/setup.ps1`, `powershell/sync.ps1`, `macos/setup.sh` |
| zsh profile on a Mac: Homebrew, `bin/` on PATH, `dotfiles-check` | `macos/zshrc` | `~/.zshrc` (symlink) | `macos/setup.sh` |
| A Mac's tools | an overlay's `macos/Brewfile` and `machines/<KEY>.Brewfile` | installed via `brew bundle` | `macos/setup.sh` |
| Agent skills | `ai/skills/<name>/`, here or in an overlay | `~/.claude/skills` and every extra Claude config folder's `skills`, `~/.codex/skills`, `~/.copilot/skills` (symlinks) | `ai/install.sh` |
| Bruno API collections | an overlay's `bruno/<collection>/` | `~/bruno/<collection>` (symlinks) | `ai/install.sh` |
| Claude Code global instructions | `ai/CLAUDE.md` | `~/.claude/CLAUDE.md` and each extra Claude config folder's (symlinks) | `ai/install.sh` |
| Claude Code sub-agents | `ai/agents/*.md` | `~/.claude/agents/` and each extra Claude config folder's (symlinks) | `ai/install.sh` |
| Claude Code settings (model, plugins, allowlist) | `ai/claude/settings.json` | merged into `~/.claude/settings.json` and each extra Claude config folder's | `ai/install.sh` |
| Extra Claude config folders, one login each | an overlay's `ai/claude/config-dirs`, and `machines/<KEY>.config-dirs` for one machine | the folders it names get the same as `~/.claude` | `ai/install.sh` |
| Skill secrets (encrypted with SOPS + age) | `ai/secrets/<skill>/`, here or in an overlay | `%USERPROFILE%\.agent-secrets\` (`~/.agent-secrets/` on a Mac), then symlinked into every checkout that has the skill (shipped skills read them in place) | `powershell/deploy-secrets.ps1`, `macos/deploy-secrets.sh` |
| Commands for every shell, agents' included (`md-lint`, `check-encrypted`, `leak-check`) | `bin/` | the user PATH | `powershell/setup.ps1`, `powershell/sync.ps1` |
| Tools and programs a machine needs | `powershell/tools.psd1`, here or in an overlay | installed via winget, npm, uv and GitHub releases | `powershell/install-tools.ps1` |
| Default markdownlint rules | `powershell/markdownlint.jsonc` | passed to `markdownlint-cli2` by `bin/md-lint` | none (used in place) |
| Automatic pull-and-relink | `powershell/sync.ps1` | Windows scheduled task "Dotfiles Sync" | `powershell/install-sync-task.ps1` |
| Automatic pull-and-relink on a Mac | `macos/sync.sh` | LaunchAgent `local.dotfiles.sync`, logging to `~/Library/Logs/dotfiles-sync.log` | `macos/install-sync-agent.sh` |
| Claude account rotation (`cswap auto`), on machines with the `claude-swap` option | none | Windows scheduled task "Claude Swap Auto", at sign-in | `powershell/install-cswap-task.ps1` |
| Claude account rotation (`cswap auto`) on a Mac that installs claude-swap | none | LaunchAgent `local.dotfiles.cswap-auto`, at login and every minute, logging to `~/Library/Logs/cswap-auto.log` | `macos/install-cswap-agent.sh` |
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

   `setup.ps1` links both PowerShell profiles and `~/.gitconfig`, writes `~/.aws/config` (when a source exists), `~/.gitconfig-overlays` and, when an overlay ships `ssh/authorized_keys`, `~/.ssh/authorized_keys`, backs up any real file it displaces, installs everything in [powershell/tools.psd1](powershell/tools.psd1), and offers to reload the profile. `install-sync-task.ps1` registers the "Dotfiles Sync" task (at logon and every 4 hours). Both are safe to re-run.

   `setup.ps1` elevates itself, but **not for the symlinks** — those work unelevated once Developer Mode is on. It elevates so winget installs the manifest machine-wide; unelevated it would quietly fall back to `--scope user`. See [ADR 0002](docs/adr/0002-mklink-not-new-item.md).

   `setup.ps1` installs NVM for Windows but no Node, so it reports the npm tools as failed. Open a new elevated PowerShell and run `nvm install lts`, `nvm use lts`, `npm config set prefix "$env:APPDATA\npm" --location=user` and `dotfiles-tools`, which installs them. The prefix keeps global npm packages in one folder for every Node version NVM holds; without it each version has its own, and npm loses sight of the ones installed under another.

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

   It clones the repo beside this one, lists its overlays in `ai\secrets\machine.local.psd1` (created from the example if missing, with `SearchRoots` set to the folder this checkout is in), and runs `sync.ps1` to apply them.

## Quick start (new Mac)

One command, on a Mac with nothing installed:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/hugoforte/dotfiles/main/macos/bootstrap.sh)" \
    bootstrap --overlays <owner>/<private-repo> --name <NAME>
```

`macos/bootstrap.sh` asks for the password once, and signs `gh` in through the browser if it is not signed in. Then it does the steps below in order: it names the Mac, installs Homebrew (with the Xcode Command Line Tools), `gh`, `jq` and `node`, clones this repo and the overlay repo into `~/source` (`--dir` for elsewhere), and writes `ai/secrets/machine.local.psd1` listing every overlay in the repo (`--only` for some). It then runs `setup.sh`, the sync agent, each overlay's own `macos/bootstrap.sh`, and the secrets deploy, and ends with the check. It is safe to re-run. By hand, the steps are:

1. Name the Mac. Its files in an overlay's `machines/` are found by its `HostName` (else its `LocalHostName`), uppercased:

   ```sh
   sudo scutil --set ComputerName <NAME>
   sudo scutil --set LocalHostName <NAME>
   sudo scutil --set HostName <NAME>
   ```

2. Install the Xcode Command Line Tools (`xcode-select --install`) and [Homebrew](https://brew.sh), then `brew install gh jq node` and `gh auth login`. The `agent-guard` hook needs `node`, and `macos/setup.sh` fails without it.
3. Clone this repo and each overlay repo, for example under `~/source`, and list the overlays in `ai/secrets/machine.local.psd1` (copy the example; the paths are POSIX paths).
4. Run the setup, and check it:

   ```sh
   sh macos/setup.sh
   sh macos/setup.sh --check
   ```

   `setup.sh` links `~/.zshrc`, `~/.gitconfig` and `~/.ssh/authorized_keys` (each when a source exists), writes `~/.aws/config` (when a source exists) and `~/.gitconfig-overlays`, applies each overlay's Brewfile and this Mac's with `brew bundle`, then runs `ai/install.sh`. It backs up any real file it displaces and is safe to re-run. `--check` changes nothing and exits 1 if anything would change; `dotfiles-check` in a new terminal runs it. `~/.zshrc` is a link into this repo, so lines that are this Mac's alone, and what installers such as nvm want to append, go in `~/.zshrc.local`, which it sources.

5. Keep the Mac in sync:

   ```sh
   sh macos/install-sync-agent.sh
   ```

   It installs a LaunchAgent that runs `macos/sync.sh` at login and every 4 hours ([ADR 0009](docs/adr/0009-a-launchagent-syncs-the-mac.md)): pull this repo and each overlay repo, run `setup.sh` (with `brew bundle` only when a Brewfile changed), and deploy the skill secrets. `dotfiles-sync` runs it now. Safe to re-run; `--uninstall` removes it.

6. Skill secrets: add the Mac as a SOPS recipient in each overlay (see [ai/secrets/README.md](ai/secrets/README.md), "Add a machine"), set `SearchRoots` in `machine.local.psd1`, and run `sh macos/deploy-secrets.sh`. The sync deploys them from then on.

## Private configuration: overlays

This repo holds nothing private. Anything that is, such as employer AWS accounts, a work email, or skill secrets whose key names say too much, lives in an **overlay**: a directory in a private repo, laid out like this repo's root. A machine lists its overlays in the git-ignored `ai/secrets/machine.local.psd1`, so no tracked file here names one. One private repo may hold several overlays, one per audience, so an employer's overlay can later move to a repo the employer owns.

What an overlay can supply, and how:

- `ai/secrets/registry.psd1` and `ai/secrets/<skill>/`: merged with every other registry; a skill id may be registered only once.
- `ai/skills/<name>/`: linked beside this repo's skills by `ai/install.sh`, for a skill whose text names something private; a skill name may be shipped from only one place.
- `ai/rules/<name>.md`: guidance beside this repo's `CLAUDE.md`, linked by `ai/install.sh` into `~/.claude/rules/` and every extra Claude config folder's `rules/`, which Claude Code reads with `CLAUDE.md`; a rule name may be shipped from only one place. Only the folder's own `.md` files are rules, not its subfolders', and every one is loaded, so keep notes about them elsewhere. This is where one person's or one employer's working rules go.
- `ai/agents/<name>.md`: agents linked beside this repo's agents; a name this repo or an earlier overlay already ships is not linked.
- `bruno/<collection>/`: linked into `~/bruno` by `ai/install.sh`, so Bruno opens every overlay's collections from one home; a collection name may be shipped from only one place.
- `ai/claude/config-dirs`: extra Claude config folders, one absolute or `~/…` path per line (`#` starts a comment). `ai/install.sh` gives each the same as `~/.claude`; see [Claude accounts](#claude-accounts).
- `machines/<KEY>.config-dirs`: the same, for one machine only, found by its Windows computer name, or on a Mac by its `HostName` (else its `LocalHostName`), uppercased.
- `aws/config`: AWS CLI profiles. Every one in this repo and the overlays is merged into a generated `~/.aws/config`, the repo first and then the overlays in the order listed; the same section in two of them is an error. Add a profile in its overlay: an edit to `~/.aws/config` is backed up and replaced on the next sync ([ADR 0010](docs/adr/0010-aws-config-is-generated.md)).
- `ssh/authorized_keys`: the public keys that may log in to the machine over SSH, put at `~/.ssh/authorized_keys` by setup and every sync; only one overlay may ship it, and this repo never does. A Mac links it. Windows gets a copy headed by a comment naming its source, which the unelevated sync rewrites whenever the source changes; a file it did not write is backed up first. Once no listed overlay ships it, setup and the sync remove the link or copy they made, so the keys stop working; `--check`/`-Check` report it until then. On a Mac, sshd follows the link and refuses the keys unless the overlay checkout and every directory above it up to your home are yours and not group- or world-writable. An administrator's account reads that file only once `sshd_config`'s `Match Group administrators` block is gone; turning the SSH server on is the overlay's to do.
- `git/gitconfig`: included, in overlay order, by the generated `~/.gitconfig-overlays`. This repo ships no name or email, so the git identity comes from here, and until one does git refuses to commit (`user.useConfigOnly`). The last setting git reads wins, so list an overlay that sets a default `[user]` before one whose `includeIf` sets another for its remotes.
- `powershell/tools.psd1`: merged with this repo's manifest by `install-tools.ps1`; a tool id may be declared only once. Its entries may be optional, so an overlay can declare its own options.
- `machines/<KEY>.psd1`: the machine's `OptionalTools`, found by its Windows computer name, uppercased, and added to those in `machine.local.psd1`, so a machine's options are tracked and survive the machine. Only one source across all overlays. The overlays themselves stay in `machine.local.psd1`, since this file is found through them.
- `macos/Brewfile`: applied on every Mac that lists the overlay, with `brew bundle`, in overlay order ([ADR 0008](docs/adr/0008-a-brewfile-per-overlay.md)).
- `machines/<KEY>.Brewfile`: one Mac's own tools, found by its `HostName` (else its `LocalHostName`) uppercased and applied after the overlays' Brewfiles. Only one source across all overlays.
- `leak-check/terms.txt`: what must never reach this public repo, one case-insensitive regular expression per line; every overlay's merge, and `leak-check` fails on a match without printing it. See [Leak check](#leak-check).
- `macos/bootstrap.sh`: run by `macos/bootstrap.sh` here, after setup and the sync agent, for the steps of a new Mac that are the overlay's to know. It must be safe to re-run; the sync never runs it.
- `machines/`: the files above that belong to one machine each, named by its key. `install-tools.ps1` warns when an overlay has this folder and no `<KEY>.psd1` in it, so a misnamed file is not silent.

The sync task pulls each overlay repo and re-applies all of these, so a change pushed to an overlay reaches every machine that lists it. Skills, rules, agents and Bruno collections are linked by `ai/install.sh`, which the sync runs before it pulls the overlays, so an overlay's change to them lands one sync later. Tools are installed after the pull, so an overlay's tool lands on the same sync. `install-overlays.ps1` is idempotent; re-run it when an overlay repo gains an overlay.

## Leak check

This repo is public, so nothing private may merge into it. `leak-check` (in `bin/`, on PATH like `check-encrypted`) checks the checkout you run it in. It fails on:

- a private term, in a file or in a file's path
- an email address outside the domains kept for examples and tests, GitHub's and Anthropic's noreply senders, and a public forge's `git@` remote
- a private key, a token, or a real SSH public key
- a UTF-16 file, which it cannot read

With `--pr <n>` it also checks that pull request's title, body, commit messages and commit authors, which are public too. A finding names the file and line (or the part of the pull request) and which rule, never what matched.

The private terms never live here. Locally they are every overlay's `leak-check/terms.txt`, from the overlays the dotfiles checkout that `leak-check` belongs to lists, so run it from a rig worktree before you push. In CI they are the `LEAK_CHECK_TERMS` repository secret, which `.github/workflows/leak-check.yml` gives the check on every pull request, and again whenever its title or body is edited. A fork's or Dependabot's pull request gets no secret, so there it runs the generic rules alone; anywhere else, an empty secret fails the run. A term that is not a valid regular expression, or matches every line, fails the check by its line number. After an overlay's terms change, refresh the secret from them:

```sh
leak-check --terms | gh secret set LEAK_CHECK_TERMS -R hugoforte/dotfiles
```

`--terms` always reads the overlays, never the secret, and refuses to print an empty list. It does print the terms, so pipe it straight into `gh` and never into a log. The overlay repo's own daily scan stays: it also covers this repo's history, every branch, and issue and pull request comments and their edit history, which a check on one pull request never sees.

## Claude accounts

Claude Code keeps its login, history and settings in one config folder, `~/.claude` unless `CLAUDE_CONFIG_DIR` names another. Two things here let work run on more than one Claude subscription without signing in and out by hand.

### Route folders: one login per kind of work

A **route folder** is an extra Claude config folder with its own login, for work that should bill a different subscription than `~/.claude` does. Which folders a machine has is private, since a folder's name usually says whose work it is for, so an overlay names them, one per line, in `ai/claude/config-dirs`:

```text
# route folders
~/.claude-client   # client work
```

A folder that only one machine should have goes in the overlay's `machines/<KEY>.config-dirs` instead, in the same format. `KEY` is the machine's Windows computer name, or on a Mac its `HostName` (else its `LocalHostName`), uppercased, the same key its other `machines/` files use. A machine reads its own file beside `ai/claude/config-dirs` and ignores every other machine's.

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

On a Mac, claude-swap is not an option but a Brewfile line: `uv "claude-swap"`, beside `brew "uv"`, in an overlay's `macos/Brewfile` or `machines/<KEY>.Brewfile`, and `brew bundle` installs it. Add the accounts as in step 1 and run `sh macos/install-cswap-agent.sh`, in either order: before any account is added, each run logs that the login is not one it manages. The script installs the LaunchAgent `local.dotfiles.cswap-auto`, which runs one `cswap auto --once` at login, now and every minute, and logs to `~/Library/Logs/cswap-auto.log`. Each run first moves a log over 1 MB to `cswap-auto.log.1`, and an upgraded claude-swap is picked up by the next run. Re-running the script with nothing changed leaves the agent alone; `--check` reports drift, and `--uninstall` removes it, which comes before uninstalling claude-swap, or the agent goes on trying to run it every minute. Keep the auto-switch in claude-swap's menu bar off: with both on, two engines poll the usage API. The Mac keeps the login in the Keychain, which Claude Code caches for about 30 seconds, so a running session moves to the new account within half a minute of a switch.

claude.ai connectors (Atlassian, Microsoft 365 and the like) belong to a claude.ai account, not to a machine, so after a switch new sessions get the other account's connectors. Set up the connectors you need on every account in the rotation.

claude-swap rotates `~/.claude` only. A route folder with one account needs no rotation.

## Keeping machines in sync

- Edit files in this repo, commit, push.
- Other machines pull and re-link automatically via the scheduled task, or the LaunchAgent on a Mac, or on demand with `dotfiles-sync` in PowerShell or zsh. Symlinked files pick up edits without re-running anything; new files need a re-link, which the sync does.
- Every installer has a report-only mode that changes nothing and exits non-zero if anything is out of sync: `./ai/install.sh --check`, `.\powershell\setup.ps1 -Check`, `.\powershell\deploy-secrets.ps1 -Check` and `dotfiles-tools -Check`, and on a Mac `sh macos/setup.sh --check` and `sh macos/deploy-secrets.sh --check`. Each reports links that are missing, replaced by a real file, or pointing elsewhere. They answer "is this machine in sync with the repo?" — not "is this code correct?", which is what `tests/` is for.
- Tools are declared in [powershell/tools.psd1](powershell/tools.psd1). Add an entry, commit, push, and every machine installs it on its next sync — the sync only does this work when a manifest, or the machine's options, have actually changed. Entries marked `Unattended = $false` are skipped by the scheduled task and wait for `dotfiles-tools`; `dotfiles-tools -Check` reports what is missing without installing anything.
- Optional tools install only on machines that ask for them. An entry with `Optional = 'openwhispr'` belongs to that option; list the name under `OptionalTools` in an overlay's `machines/<KEY>.psd1` (or in `ai/secrets/machine.local.psd1`) and run `dotfiles-tools` to install it, its first-run step included. Machines that don't list it are told it is available. A machine without skill secrets can write that file just for `OptionalTools`: the sync deploys secrets only when it also declares `SearchRoots`.

## Layout

- [powershell/](powershell/README.md): profile, setup, sync, AWS, Git and rig helper functions
- `macos/`: a Mac's setup and its check, sync and its LaunchAgent, secrets deploy, `zshrc` and `gitconfig`
- [aws/](aws/README.md): how the AWS CLI config is supplied
- [ai/](ai/README.md): agent skills, Claude Code config, installer
- [.github/](.github/instructions/README.md): Copilot instructions and reusable prompts
- [tests/](tests/README.md): fixture tests for the parts that can be tested without touching the machine you are on; CI runs them on every pull request
- [GLOSSARY.md](GLOSSARY.md): the glossary — what "managed", "drift", "checkout" and the rest mean here
- [docs/adr/](docs/adr/): the decisions a reader would otherwise try to undo, and why
- [docs/agents/](docs/agents/): issue tracker, triage labels and domain-doc conventions read by the engineering skills
- [RELEASES.md](RELEASES.md): change log
