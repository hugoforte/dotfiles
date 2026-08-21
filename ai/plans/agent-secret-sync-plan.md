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

## 2. Architecture

To be defined after selecting the encryption/key-management approach and target-discovery rules.

## 3. Proposed implementation

To be defined after the architecture is approved.
