---
name: resolve-pr-comments
description: Work through the review comments on a pull request — action the ones worth actioning, reply to every one, and resolve the threads. Use when asked to resolve, address, action or clear PR comments or review feedback.
---

# Resolve PR comments

Take a pull request's review feedback to zero: for each comment, decide whether to action it, do the work if so, reply in the thread, and resolve it.

`$ARGUMENTS` may be a PR number, a PR URL, or empty. Empty means the PR for the current branch.

## Step 1: Identify the PR

```bash
gh pr view $ARGUMENTS --json number,title,headRefName,baseRefName,state,url,isCrossRepository
```

Stop if the PR is merged or closed, or if the current branch has no PR — say so rather than guessing at another PR.

Check out the head branch and make sure the working tree is clean before touching anything:

```bash
gh pr checkout <number>
git status --short
```

A dirty tree means someone else's work is in flight. Stop and ask.

## Step 2: Collect the comments

Two kinds of comment live on a PR and they behave differently.

**Review threads** (inline, on a line of the diff). These are the ones that can be resolved:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes { databaseId author { login } body createdAt }
          }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<number>
```

**Issue comments** (top-level, on the conversation tab). They have no resolved state:

```bash
gh pr view <number> --json comments --jq '.comments[] | {author: .author.login, body}'
```

Skip threads where `isResolved` is true. Skip comments authored by me — my own notes are not feedback to action. Handle `isOutdated` threads: the code they point at has moved, so read the current file before deciding whether the point still stands.

Read the PR diff once for context: `gh pr diff <number>`.

## Step 3: Decide on each comment

For each unresolved thread, read the file it points at as it is now, then classify it:

- **Action it** — a real bug, a correctness or security problem, a convention the repo actually follows, a test gap, or a clear improvement the author would accept.
- **Don't action it** — a question rather than a request, already fixed elsewhere in the branch, a matter of taste that cuts against the codebase's existing patterns, out of scope for this PR, or factually mistaken about what the code does.

Out-of-scope but worth doing is still "don't action it" here: note it for a follow-up issue instead of widening the PR.

Check the repo's `CLAUDE.md`, `AGENTS.md` and any `.github/instructions/` before calling a style point wrong — the reviewer may be quoting a standard.

## Step 4: Confirm the plan

Present a table before changing anything or posting anything:

| # | File:line | Comment (short) | Decision | What I'll do |
|---|---|---|---|---|

Say plainly which comments you propose to push back on and why. Then wait for approval. Do not commit, comment, or resolve until the user approves — replies and resolutions are public and hard to take back.

If the user disagrees with a decision, re-decide that row and re-present; don't argue past one exchange.

## Step 5: Do the work

For each **action it** comment, in file order so related edits land together:

1. Write or update the test first where the project has tests for that area.
2. Make the smallest change that addresses the comment. Nothing else — unrelated cleanup belongs in its own PR.
3. Run the project's tests, linter and formatter. A failing build stops the run; fix it before moving on.
4. Commit on its own, imperative subject, referencing the thread:

   ```bash
   git commit -m "Validate the callback URL before redirecting

   Addresses review comment from @reviewer on src/auth/callback.ts."
   ```

Push once, after all the fixes are in, so the replies can cite real SHAs:

```bash
git push
```

## Step 6: Reply and resolve

Only after the push. Per thread, reply to the **last** comment in it so the reply lands in-thread rather than as a new root comment:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_databaseId>/replies \
  -f body="Fixed in <sha> — <one line on what changed>."
```

For a comment not actioned, say why in the same place, briefly and without defensiveness:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_databaseId>/replies \
  -f body="Leaving this as-is: <reason>. Happy to change it if you feel strongly."
```

Then resolve the thread:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) { thread { isResolved } }
}' -F threadId=<thread node id>
```

Top-level issue comments cannot be resolved. Reply with `gh pr comment <number> --body "…"` and leave it at that.

Reply in the reviewer's language and keep it to one or two sentences. State what happened; don't thank, apologise, or re-explain the code.

## Step 7: Report

Close with:

- Comments actioned, each with its commit SHA
- Comments declined, each with the reason given
- Threads resolved, and any left open (with why — an unanswered question, a decision that needs the reviewer)
- Follow-up issues worth filing for the out-of-scope points

Re-run the Step 2 query to confirm nothing unresolved is left behind, and report the count honestly if some remain.
