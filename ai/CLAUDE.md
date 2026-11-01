# Development Guidelines

<!-- Every line here loads in every session, so each one must change behaviour against the model's and Claude Code's defaults. Guidance for one kind of file goes in ai/rules/ with a `paths:` filter; guidance for one repo goes in that repo. An overlay's ai/rules/*.md are linked into ~/.claude/rules/ beside this repo's. -->

## Environment

- Global agent config lives in `~/.claude`, symlinked from the `dotfiles` repo. Change it in the repo, not through `~/.claude`.
- Rules that hold in every repo belong here, not in a project's auto-memory: memory is kept per starting folder, so a rule saved from one folder is missing in a session started in another.
- Write files and scripts with Write and change them with Edit, then run them. Never write one through a heredoc or edit one with `perl -i` or `sed -i`, because quotes and backslashes break on the way through the shell; the `agent-guard` hook refuses those commands.
- "Continue from where you left off" after a crash, a usage limit or an API error means resume the unfinished task.

## Acting outside the work

- Inside the work and reversible: take the obvious next step and say so. Do not ask a question that has one answer.
- Never merge, close, delete or transition a PR, issue, ticket, branch or rig work unless the user named that item for that act. "Check" or "see which can" means report only. The `agent-guard` hook asks before `gh pr merge`, `gh stack merge` and merges through `gh api`.
- Once a branch's PR has merged and every commit on it is on the base, delete it on the remote and locally (`git branch -d`) without asking. A branch with commits the base lacks stays; say which commits.
- When asked to look, check or explain, change nothing on disk; propose instead.
- Send no request to a production host unless asked. Read-only database queries are fine through a skill that says so.
- Before reporting state — a PR's checks, whether it merged, a stack, a deploy — query it again; never repeat it from earlier in the session. Do not call a failing required check unrelated or pre-existing until you show it fails the same way on the base.

## Code

- Find three similar things in the codebase before writing a fourth, and follow them.
- Code added on the current branch is not legacy: change it freely instead of adding a parallel method to preserve compatibility. Only code already on the main branch counts as legacy.
- Fail fast with descriptive errors that include context, and let exceptions surface rather than swallowing them.
- Add a dependency only when it replaces more than a one-liner of your own code, and write down why.
- A TODO carries an issue number.
- Fix a linter or tool warning rather than suppressing it, unless you say why.
- After two failed attempts at one issue, stop and hand it to the `bug-root-cause-analyzer` agent.

## Testing

- Call a fix verified only once the test that proves it has failed without the fix.
- A failing test gets fixed, never disabled to make a run green.

## Git and GitHub

- Every commit compiles, passes the existing tests, includes tests for new behaviour, and is formatted with the project's formatter.
- A commit that fixes an issue carries `Fixes #123` on its own line.
- Post PR review comments only with the user's explicit approval. Reply to an existing review thread in that thread, not at the root.

## Comments and docs

- Comment on the code as it is: say what it does now, not the change that produced it.
- Comment only what the code cannot say itself.
- Update the documentation a behaviour change affects, in the same change.
- Use a real ellipsis (…) rather than three dots in human-facing text.
