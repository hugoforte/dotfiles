---
name: hf-resolve-pr-comments
description: Work through the review comments on a pull request — action the ones worth actioning, reply to every one, resolve automated reviewers' threads, then make sure the PR is mergeable with its base. Use when asked to resolve, address, action or clear PR comments or review feedback.
---

# Resolve PR comments

Work through a pull request's review feedback: for each comment, decide whether to action it, do the work if so, and reply in the thread. Resolve an automated reviewer's thread; a person's thread is theirs to resolve, so it stays open. Then make sure the PR is good to go with its base: no threads left is not done while the base has moved on and conflicts with it.

`$ARGUMENTS` may be a PR number, a PR URL, or empty. Empty means the PR for the current branch.

## Step 1: Identify the PR

```bash
gh pr view $ARGUMENTS --json number,title,headRefName,baseRefName,state,url,isCrossRepository
```

Stop if the PR is merged or closed, or if the current branch has no PR — say so rather than guessing at another PR.

Work in the PR's own worktree, never the repo's checkout. In a rig work, that is the repo's worktree there, already on the branch. Outside one, check the head branch out into a worktree beside the repo's checkout, outside rig's work root:

```bash
gh pr checkout <number> --worktree ../<repo>-pr-<number>
```

Either way, make sure that worktree is clean before touching anything:

```bash
git -C <worktree> status --short
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
            totalCount
            nodes { databaseId author { login __typename } body createdAt }
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

Say plainly which comments you propose to push back on and why.

A thread only automated reviewers have written in, every comment's author a `Bot` (`__typename` in Step 2's query; CodeRabbit is one) or you, goes ahead without waiting: carry out its row through the steps below, commit, push, reply and resolve, and report it with the rest, even while other rows wait. A push-back on a bot's finding goes ahead too, its reasons in the reply. Two such threads still wait: one with more comments (`totalCount`) than the query fetched, since a human may have written in the rest, and one whose bot asks a question only the author can answer, such as whether a behaviour is intended. For every other row, wait for approval. Do not commit or comment in a human's thread until the user approves — replies are public and hard to take back. Approval does not extend to resolving it, so don't offer that in the plan.

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
head="$(gh pr view <number> --json headRefName --jq .headRefName)"
branch="$(git branch --show-current)"
remote="$(git config "branch.$branch.pushRemote" || git config "branch.$branch.remote")"
git push "$remote" "HEAD:refs/heads/$head"
```

Push to the PR's head by name, never a bare `git push`: in a rig work the branch's upstream is its base, and a bare push either fails or pushes onto the base. The remote is the one the branch tracks, which `gh pr checkout` points at the fork for a cross-repository PR. The branch name comes from the PR's author, so it goes through a quoted variable and never into the command text, where a shell would expand it.

## Step 6: Reply, and resolve an automated reviewer's thread

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

Then resolve the thread, if only automated reviewers wrote in it (Step 4), or the user wrote it and told you to:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) { thread { isResolved } }
}' -F threadId=<thread node id>
```

Leave any other thread open. A person's thread is theirs to resolve once they have read the reply, even when the user approved the plan: the reviewer decides whether the point is settled. A base that requires resolved threads then waits on that person, so say so in the report.

Top-level issue comments cannot be resolved. Reply with `gh pr comment <number> --body "…"` and leave it at that.

Reply in the reviewer's language and keep it to one or two sentences. State what happened; don't thank, apologise, or re-explain the code.

## Step 7: Make sure it is good to go with its base

A PR with every thread resolved can still be unmergeable: another PR lands on the base and edits the same lines. Look before reporting.

```bash
git fetch origin
base="$(gh pr view <number> --json baseRefName --jq .baseRefName)"
gh pr view <number> --json mergeable,mergeStateStatus
git rev-list --count "HEAD..origin/$base"
```

The base name goes through a quoted variable for the same reason as the head's in Step 5.

`mergeable` is `UNKNOWN` until GitHub has computed it. Ask again until it is `MERGEABLE` or `CONFLICTING`; never read `UNKNOWN` as clean.

When the base has commits the branch lacks, merge the base in:

```bash
git merge "origin/$base"
```

Merge, don't rebase: a rebase rewrites the commits the replies in Step 6 cite. On a conflict, resolve each hunk by keeping both sides' intent and commit the merge. Then, conflict or not, run the project's tests, linter and formatter as in Step 5: a clean merge can still break the build. Push as in Step 5.

When a conflict needs a decision only the author can make — both sides changed the same behaviour in incompatible ways, or keeping both would contradict one of them — stop. Run `git merge --abort`, present the conflicting hunks with what each side meant, and ask. Don't guess.

After the push, query the PR again and read it as it is then:

```bash
gh pr view <number> --json mergeable,mergeStateStatus
gh pr checks <number>
```

A push sets `mergeable` back to `UNKNOWN` while GitHub recomputes it: ask again, as before the merge, and never report `UNKNOWN` as the answer. A check still running is pending, not passed. When the user wants a final answer, wait for it with the agent host's own pull-request watch where it has one, else `gh pr checks <number> --watch` run in the background; otherwise report it as pending.

## Step 8: Report

Close with:

- Comments actioned, each with its commit SHA
- Comments declined, each with the reason given
- Threads resolved, and any left open: a person's, answered and waiting on them to resolve it, or an automated reviewer's, with why
- Follow-up issues worth filing for the out-of-scope points
- Whether the PR is mergeable with its base: `mergeable`, `mergeStateStatus` and each check as last queried, and what was merged in to get there (the base's commits, and the conflicts resolved), or the conflict left for the author

Re-run the Step 2 query, and report honestly how many threads stay open, and whose.
