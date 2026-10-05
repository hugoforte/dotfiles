---
name: hf-adversarial-review
description: Set a subagent on a pull request to find what is wrong with it, fix what it finds, and push. Use when asked for an adversarial review, to harden a rig work's PRs, or to review and fix a PR before handing it to the team.
---

# Adversarial review

A subagent hunts a pull request for what is wrong with it. You verify each finding against the code, fix the real ones, push to the PR's branch, and hand back a summary.

`$ARGUMENTS` may be PR numbers, PR URLs, or empty.

The run stops for the user exactly once, at Step 1, and then goes to the end on its own. Nothing is posted to GitHub: findings go to the user in chat, and the only write is a push of commits to the PR's own branch.

## Step 1: Choose the PRs

```bash
rig status
```

Inside a rig work that prints the work's repos, their worktrees and their PRs. Present them as a numbered list — repo, PR number, title — and ask in plain text whether to take all of them or which ones. Wait for the answer. Ask as text rather than with the question tool: a work can carry more repos than that tool takes options.

`not inside a work` means the target is whatever `$ARGUMENTS` names, else the PR already under discussion in this conversation, else the current branch's:

```bash
gh pr view $ARGUMENTS --json number,title,url,headRefName,state,isDraft
```

Drop merged and closed PRs from the set and name the ones you dropped. If nothing is left, or the branch has no PR, say so and stop rather than reaching for a different PR.

Each PR needs a checkout to work in. A rig work already has one worktree per repo, on the branch. Outside one, `gh pr checkout <number>`. Either way `git status --short` must come back empty before you touch anything — a dirty tree is someone's work in flight, so stop and ask.

## Step 2: Set a reviewer on each PR

One subagent per PR, dispatched in a single message so they run concurrently, in the background. Give each this brief with the PR filled in:

```text
Adversarially review pull request <url>, working in <checkout path>.

Assume this diff is wrong. Your job is to find how — not to summarise it, not to praise it.

Read, in this order:
- the whole diff: gh pr diff <number>
- every file the diff touches, in full, as it stands now
- the repo's CLAUDE.md, AGENTS.md, GLOSSARY.md and docs/adr/ where they exist
- the tests covering the touched code, and how neighbouring code solves the same problem

Hunt for:
- the input that breaks it: empty, null, zero, enormous, unicode, concurrent, out of order
- error paths that swallow, that log and carry on, or that leave state half-written
- behaviour changed under existing callers already on the base branch
- a test that asserts the implementation rather than the behaviour, and new behaviour with no test at all
- secrets, tokens or personal data reaching logs, error messages or committed files
- a convention this repo actually follows, broken here
- code, config or documentation the diff leaves stale

Rules:
- Change nothing. This is read-only; the caller applies the fixes.
- Every finding carries a concrete failure scenario: the input or sequence, and the wrong result it produces. No scenario, no finding.
- Say a category came up empty rather than inventing something to fill it.

Return a table, most severe first: severity (bug / risk / test gap / convention), file:line, the defect in one sentence, the failure scenario, the fix you suggest.
```

Then wait. The notification arrives when a subagent finishes; do not poll for it, and do not write down results before they land. A reviewer that comes back with nothing usable gets one re-dispatch with a narrower brief, then you move on with what you have.

## Step 3: Verify every finding

A finding is a claim, not a fact — the reviewer read the code under instructions to distrust it, and some of what it returns will be imagined.

Open the code each finding points at and walk its failure scenario against what is actually there. **Fix it** if the scenario holds, or if it is a leak, a missing test for new behaviour, or a convention the repo demonstrably follows. **Drop it** if a caller already guards the case, if it is taste dressed as a defect, if the reviewer misread the code, or if it is real but out of this PR's scope — that last one becomes a follow-up in the report, not a wider diff.

Every dropped finding is reported with its reason. Dropping one costs nothing; a commit fixing an imagined bug costs the PR's reviewer their trust in the whole diff.

## Step 4: Fix, verify, push

Per PR, in its own checkout:

1. Write the test first where the touched area has tests.
2. Make the smallest change that kills the finding, and nothing besides — unrelated cleanup belongs in its own PR.
3. Run what verifies the repo: `rig check <repo> --run` inside a work, otherwise the project's own test, lint and format commands.
4. Commit per finding or per tight group of them, imperative subject, with the scenario as the body:

   ```bash
   git commit -m "Reject an empty callback URL before redirecting

   Adversarial review: an empty next param redirected to the site root with the session cookie still attached."
   ```

5. Push once, after that PR's fixes are all in and green: `git push`. Only ever a plain push — the branch is under review and its history is public.

Two attempts at a green build is the limit on any one PR. Past that, leave it unpushed, carry on with the other PRs, and report what failed and where you stopped.

## Step 5: Hand back

One section per PR:

- Findings raised, and how many survived Step 3
- Each fix, with its commit SHA and one line on what changed
- Each dropped finding, with the reason
- Test, lint and format status as of the push
- Follow-ups worth their own issue

Close with the PRs that now differ from when the run started, and say plainly that you are ready for the user again.
