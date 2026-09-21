# dotfiles

One repo that configures every Windows development machine its owner uses. Files live here once and reach each machine by symlink, so an edit in the checkout is live immediately and reaches the other machines through git.

## Language

### What the repo manages

**Managed**:
Declared by this repo, and therefore this repo's to set and to report on. The word is the same for a link, a settings key and a skill secret, and it always means the same thing.
_Avoid_: owned, controlled, tracked (that means "in git")

**Unmanaged**:
Present on a machine but not declared here, and therefore left alone in every direction. This is the property that lets the installers be non-destructive: `~/.claude/settings.json` keeps its machine-local keys, and the repo's fragment never acquires them.
_Avoid_: foreign, external, user-owned

**Source**:
The file in this repo that a managed path is pointed at, or merged from.
_Avoid_: origin (that is a git remote, and `registry.psd1` uses it that way)

**Target**:
The path on the machine that a source is installed to. Every interface here takes the target first and the source second.
_Avoid_: destination, link path, dest

**Fragment**:
`ai/claude/settings.json`: a partial settings document merged into the live file rather than replacing it. The only managed thing that is merged instead of linked, because Claude Code writes to the same file.
_Avoid_: settings file, config (both are ambiguous with the live file)

**Live file**:
The machine's copy of something the repo also has a source for. Named to be said out loud against "the fragment" or "the source".
_Avoid_: installed file, real file (that means "not a symlink")

### The two kinds of managed thing

**Managed link**:
A target that is a symlink to a source. Five of them are `setup.ps1`'s; the rest are `ai/install.sh`'s. `powershell/managed-link.ps1` is the one implementation.
_Avoid_: symlink (that is the mechanism, not the concept), dotfile link

**Managed key**:
A leaf path of the fragment, where arrays count as leaves and objects do not. Nothing outside that set is read or written in any direction.
_Avoid_: setting, key (unqualified)

**Displace**:
To move a real file that is sitting where a managed link belongs. It is moved, never deleted, and the link is then made. One policy, both languages.
_Avoid_: overwrite, replace, clobber

### Being in sync, or not

**Drift**:
A difference between a machine and the repo that re-running the installer would fix. Deliberately narrower than "any difference": live-only additions under a managed key are not drift, and neither is a failed decrypt, because no amount of re-running corrects either.
_Avoid_: diff, delta, out of sync

**Check**:
A report-only run: it says what would change and changes nothing. Every installer has one. It answers "is this machine in sync with the repo?", never "is this code correct?" — that question is the test suite's.
_Avoid_: verify, validate, test

**Component**:
One unit `ai/install.sh` installs, checks and uninstalls: CLAUDE.md, agents, skills, settings, secrets. Each has an `install_`, `uninstall_` and `check_` of its own.
_Avoid_: module, feature, part

**Sync**:
The scheduled pull-and-relink: `git pull --ff-only`, then the installers. A machine is synced by it; a machine that matches the repo is *in sync*, which is a state, not this.
_Avoid_: update, refresh

### Machines

**Machine**:
One Windows install with a checkout of this repo. Its identity is its SSH key, and it opts into skill secrets by having a `machine.local.psd1`.
_Avoid_: host, box, device

**Checkout**:
A working copy of *another* project's repo, found one level under a search root, which may host a project skill needing secrets. This repo's own working copy is "the repo" or "the dotfiles checkout" — never a bare "checkout".
_Avoid_: clone, workspace, project (unqualified)

**Search root**:
A directory on a machine whose immediate children are checkouts, listed in `machine.local.psd1`. Per machine and git-ignored, because it is a local layout, not a shared fact.
_Avoid_: source root, projects directory, workspace

### Skills

**Shipped skill**:
A skill this repo owns, under `ai/skills/<name>/`, linked *out* into each agent's skills directory on every machine.
_Avoid_: skill (unqualified), global skill

**Project skill**:
A skill owned by another repo, living in that checkout's `.claude/skills/<id>/`. This repo does not supply the skill, only its secrets.
_Avoid_: skill (unqualified), local skill, app skill

### Secrets

**Skill secret**:
A credential a project skill needs, committed here encrypted and symlinked into every matching checkout. Plaintext never enters git, in this repo or the app repos.
_Avoid_: credential, env file, secret (unqualified)

**Recipient**:
An age public key that can decrypt the secrets. Every machine is one, via its SSH key, and so is the recovery key held in the password manager.
_Avoid_: key holder, member

**Marker**:
The path, relative to a checkout root, whose presence identifies that checkout as using a given project skill. Paired with an expected origin so a same-named skill elsewhere is not matched.
_Avoid_: detector, sentinel, probe

**Registry**:
`ai/secrets/registry.psd1`: the tracked declaration of every managed skill secret — its id, marker, expected origin and files.
_Avoid_: manifest (that is the tools one), catalogue, index

### Tools

**Manifest**:
`powershell/tools.psd1`: the tools and programs a machine needs, declared. Entries install only when missing; nothing is ever upgraded or uninstalled, because a program on the machine and not in the manifest was installed on purpose.
_Avoid_: package list, registry (that is the secrets one), tools file

**Deferred entry**:
A manifest entry marked `Unattended = $false`: safe to install only on a watched run, so the scheduled task reports it and leaves it. Not a failure, and it does not hold back the manifest hash.
_Avoid_: skipped, blocked, manual (that is a `Source`, for entries nothing can install)

### Reporting

**Outcome**:
One reported fact about a run, of exactly five kinds — ok, changed, warned, to do, error. Each prints a line and records it; anything that is not one of those is chatter and only prints.
_Avoid_: message, log line, status

**Result**:
What a script returns to a caller: the counts of each outcome, plus the messages. It exists because `Write-Host` does not survive a call boundary in Windows PowerShell 5.1, so a caller that reads printed output reads nothing.
_Avoid_: output, report, summary (that is the closing line, which is deliberately not recorded)
