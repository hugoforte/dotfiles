# Development Guidelines

## Environment

- Windows 11. PowerShell 5.1 is the primary shell; Git Bash is available for POSIX scripts.
- Prefer `gh` for GitHub operations; never the GitHub MCP tools.
- Global agent config lives in `~/.claude`, symlinked from the `dotfiles` repo. Edit the repo, not the symlink target.
- Rules that hold in every repo belong here, not in a project's auto-memory: memory is kept per starting folder, so a rule saved from one folder is missing in a session started in another.
- Write files and scripts with Write and edit them with Edit, then run them. Never write a file or a script through a heredoc, or edit one in place with `perl -i` or `sed -i`: quotes and backslashes break on the way through Git Bash. The `agent-guard` hook refuses those commands.
- Git Bash's `/tmp` is not the `/tmp` that Windows-native node, python and gh see. Hand them Windows paths (`cygpath -w`).
- Wait for CI with `gh pr checks <n> --watch` run in the background, never `sleep`.
- "Continue from where you left off" after a crash, a usage limit or an API error means resume the unfinished task.

## Acting outside the work

- Inside the work and reversible: take the obvious next step and say so. Do not ask a question that has one answer.
- Never merge, close, delete or transition a PR, issue, ticket, branch or rig work unless the user named that item for that act. "Check" or "see which can" means report only. The one exception is rig's own: `rig stage --land` merges reviewed stages into the work branch, never further. The `agent-guard` hook asks before `gh pr merge`, `gh stack merge` and merges through `gh api`.
- When asked to look, check or explain, change nothing on disk; propose instead.
- Send no request to a production host unless asked. Read-only database queries are fine through a skill that says so.
- Before reporting state — a PR's checks, whether it merged, a stack, a deploy — query it again; never repeat it from earlier in the session. Do not call a failing required check unrelated or pre-existing until you show it fails the same way on the base.

## Philosophy

- **Incremental progress over big bangs**: small changes that compile and pass tests.
- **Learn from existing code**: find three similar things in the codebase before writing a fourth.
- **Pragmatic over dogmatic**: adapt to the project's reality.
- **Clear intent over clever code**: be boring and obvious. If it needs explaining, it is too complex.
- **Simple code** passes the tests, expresses every needed idea, says everything once, and has no superfluous parts. Balance those in favour of future maintainers.
- Work in three stages: make it work, make it right, make it fast.

## Backwards compatibility

Code added on the current branch is not legacy. Change it freely instead of adding a parallel method to preserve compatibility. Only code already on the main branch counts as legacy.

## Agents

| Situation | Agent |
|---|---|
| Complex feature (more than 3 stages or unclear requirements) | `implementation-planner` first |
| Test-first development | `unit-test-writer` before implementing |
| Stuck after 2 failed attempts | `bug-root-cause-analyzer` |
| Before committing | `code-reviewer` |
| Non-obvious discovery worth keeping | `note-taker` |
| A prompt or agent definition needs improving | `prompt-optimizer` |
| Unsure which agents to use | `task-orchestrator` |

**Maximum 2 attempts per issue**, then stop and use `bug-root-cause-analyzer`. It documents what failed, researches alternatives, questions the abstraction, and investigates systematically.

Notes, plans and reviews written by agents go under `~/ai-notes/`:

- `~/ai-notes/plans/{org}/{repo}/{issue-or-branch-or-slug}.md`
- `~/ai-notes/notes/{org}/{repo}/{area}.md`
- `~/ai-notes/reviews/{org}/{repo}/{issue-or-branch-or-slug}.md`

Project-local scratch goes in `.notes/` or `notes/`, never the repo root.

## Process

1. **Understand**: read the README and other top-level markdown first. Study existing patterns.
2. **Test**: write the test first when practical.
3. **Implement**: minimal code to pass.
4. **Refactor**: clean up with tests green.
5. **Commit**: clear message explaining why.

## Technical standards

- Composition over inheritance; interfaces over singletons; explicit over implicit.
- Fail fast with descriptive errors that include context. Never silently swallow exceptions.
- Use the project's existing build system, test framework, formatter and linter. Do not introduce new tools without strong justification.
- Avoid new dependencies for one-liners. Prefer battle-tested libraries over trendy ones. Write down the rationale when adding one.
- Every commit compiles, passes existing tests, includes tests for new behaviour, and follows the project's formatting.
- Run the project's formatter before committing.

## Definition of done

- Tests written, passing, and not redundant
- No dead code; minimal code to get the job done
- Follows project conventions; no linter or formatter warnings
- No tool warnings ignored without strong justification
- Implementation matches the plan, and the plan status is updated
- No TODOs without issue numbers

## Testing

- Test behaviour, not implementation.
- One assertion per test when possible; clear names describing the scenario.
- Deterministic tests. Never disable a test to make a run green; fix it.
- Always run tests before calling a task complete.
- Call a fix verified only once the test that proves it has failed without the fix.

## Git

- Commit messages: present tense, imperative ("Add", "Fix", "Remove"). One-line summary, blank line, optional body explaining why.
- When a commit fixes an issue, add `Fixes #123` on its own line.
- Keep commits clean. Squash when appropriate; no "WIP" commits unless spiking.
- Never bypass commit hooks with `--no-verify`. Never commit code that does not compile.

## GitHub

Use the `gh` CLI for everything GitHub: issues, PRs, checks, releases, and `gh api` for anything else. WebFetch is only for public documentation pages.

Write a PR body with the `matt-pr` skill, unless the repo has a PR template; then fill that in. In a rig work, write it into the context doc's `## Pull request` section with its headings at `###` (`rig pr` raises them to `##`; a `##` would end the section), and let `rig pr` lift it; never edit a rig PR's body on GitHub.

Finished rig work ends in a pushed PR. Every PR, issue, comment or run you create or mention gets its full URL, never a bare `#123`.

Never post PR review comments without explicit approval. When replying to an existing review thread, reply in-thread rather than creating a root-level comment.

## Comments and docs

- Comment on the code as it is, not as it was. Describe what the code does now, not the change that produced it.
- Do not comment self-explanatory code.
- Update relevant documentation when behaviour changes, in the same change.
- Use a real ellipsis (…) rather than three dots in human-facing messages.

## Markdown

- Consistent heading levels, blank lines around headings and code blocks, one list marker style, no trailing whitespace.
- Never hard-wrap lines when editing markdown; preserve the existing line structure.
- Run `md-lint <file>` on edited markdown files. It is a command in the dotfiles `bin/`, on PATH in every shell, that wraps `markdownlint-cli2` and supplies the dotfiles default rules; a repo overrides them by shipping its own `.markdownlint-cli2.jsonc`. `markdownlint-cli2` arrives via `powershell/install-tools.ps1`, and `bin/` reaches PATH via `setup.ps1` or the sync task.

## Shell scripts

- Use plain `echo` or the helpers in `ai/helpers/output.sh`; do not invent per-script logging functions.
- Check optional tools with `command -v` before using them.