# Agent Skill and Secret Sync Plan

## 1. Requirements

### Goals

- Keep personal, user-level AI skills and related configuration portable across Windows machines.
- Use the personal `dotfiles` repository as the canonical, versioned source for this setup.
- Support Claude Code, Codex, and future configurable agent-skill directories without syncing complete tool home directories.
- Synchronize actual credentials needed by skills without committing plaintext credentials to an application or company repository.
- Allow either machine to make changes and synchronize those changes through Git. Near-real-time synchronization is not required.
- Work when a machine is offline after its local configuration and secrets have been deployed.
- Use Tailscale as an available private-network transport option; do not require fixed checkout locations or a shared drive.
- Provide a reusable, versioned onboarding skill in this repository for adding managed skills and setting up new machines.

### employer-app DB-query skill

- The `app-db-query` skill is versioned with its application repository at `.claude/skills/app-db-query`.
- Its local credential files, `.secrets.env` and `keys.local.json`, must remain ignored by that application repository.
- The canonical, encrypted counterparts of those files must be stored separately in the personal dotfiles repository.
- A deployment process must materialize usable local copies of the credential files without exposing them to Git in plaintext.

### Checkout independence

- A repository may be checked out at different paths on different machines.
- A machine may have more than one checkout of the same repository, all of which should use the same skill-secret profile unless explicitly configured otherwise.
- The deployment process must identify targets by a stable marker (such as the `app-db-query` skill directory and optionally the repository remote), not by a hard-coded absolute checkout path.
- Each machine may configure its own set of search roots, such as `C:\\git` on one machine and `C:\\source` on another.

### Security and operational constraints

- Plaintext secret files must never be committed to the dotfiles repository or the application repository.
- Encryption keys/private identities must remain local to each authorized machine and outside Git.
- Decrypted files should have a stable, user-level location and be linked or deployed into matching checkouts.
- The deployment process must be idempotent, preserve or back up unexpected existing local files, and clearly report each target it changes.
- The approach should support a future need for separate named secret profiles (for example, a normal development profile and a privileged production profile).

### Synchronization behavior

- Git is the synchronization mechanism for tracked dotfiles configuration and encrypted secret files.
- A scheduled process may automatically run `git pull --ff-only` followed by deployment; it must not automatically create commits or push changes.
- Manual synchronization remains supported through a single command that pulls, validates, decrypts, and deploys.
- Changes to tracked configuration, skills, and encrypted secret files are committed and pushed deliberately by the user from either machine.
- A failed pull, merge requirement, decryption failure, or deployment validation failure must leave the last known-good deployed secrets in place and report an actionable error.

### Onboarding workflow

- The repository must include a reusable onboarding skill that documents and guides both new-skill registration and new-machine setup.
- Adding a managed skill must have a defined workflow: place versioned material in its appropriate repository, register it, add templates and encrypted secret profiles when needed, validate deployment, and commit the registry change.
- Setting up a new machine must have a defined workflow: clone dotfiles, install prerequisites, restore the local encryption identity from a secure out-of-band source, configure local search roots, clone application repositories, and run deployment.

## 2. Architecture

### Canonical configuration

- `dotfiles/ai/sync/skills.psd1` is the tracked registry of every managed skill, its stable identifier, discovery marker, optional expected Git remote, target files, and supported secret profiles.
- Project-specific skills remain in their application repository. Global skills and shared agent configuration live in dotfiles. The registry provides a single view of both kinds.
- `dotfiles/ai/sync/secrets/<profile>/` contains SOPS-encrypted secret files. It contains no plaintext credentials.
- `dotfiles/ai/skills/agent-sync-onboarding/SKILL.md` is the reusable skill for adding a managed skill or onboarding a new machine.

### Per-machine state

- Each machine has an ignored `machine.local.psd1`, created from a tracked example, that defines local checkout search roots and optional deployment preferences.
- The machine decrypts each authorized profile to `%USERPROFILE%\\.agent-secrets\\<profile>`. Private age identities remain outside Git and are restored through a secure out-of-band path.
- Matching checkouts receive file symbolic links to the local decrypted profile files. This lets any number of checkout paths share a single local plaintext secret without drift.

### Discovery and deployment

- The deployment script searches only the configured local roots, identifies a skill from its configured marker, and optionally verifies its Git remote before linking files.
- It validates the registry and all target paths before making changes, backs up unexpected regular files, and is safe to run repeatedly.
- The script never scans or synchronizes entire `.claude`, `.codex`, or other tool-home directories.

### Sync model

- The private dotfiles Git remote is the source of synchronization. Tailscale can host or provide access to that remote, but is not required when using the existing private GitHub remote.
- The baseline command is `Sync-AgentConfiguration`: `git pull --ff-only`, validate, decrypt changed profiles, discover targets, and deploy links.
- An optional Windows Task Scheduler task runs the same command at sign-in and on a modest recurring interval. It only pulls and deploys; commits and pushes are always user-initiated.

## 3. Proposed implementation

1. Install and configure SOPS and age on both machines; create an age identity per machine and add each public recipient to `.sops.yaml`.
2. Add the sync registry, ignored machine-local configuration pattern, and encrypted `app-db-query` profile to dotfiles.
3. Implement PowerShell commands to validate the registry, discover checkouts, decrypt profiles to `%USERPROFILE%\\.agent-secrets`, and create or refresh file symbolic links.
4. Add `agent-sync-onboarding`, a skill with checklists and commands for registering a skill, provisioning a machine, rotating a recipient, and diagnosing deployments.
5. Add `Sync-AgentConfiguration` for manual pull-and-deploy, plus an optional Task Scheduler installer for automatic pull-and-deploy at sign-in and on a configured interval.
6. Validate with the employer-app DB-query skill using multiple checkout paths and confirm that no plaintext secret becomes tracked in either repository.
