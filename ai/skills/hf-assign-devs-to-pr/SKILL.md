---
name: hf-assign-devs-to-pr
description: Put a pull request in front of the team — ask which developers should take it, then request their review and assign them on GitHub. Use when asked to assign devs to a PR, add reviewers, or put a PR up for review.
---

# Assign devs to a PR

Ask who should take a pull request, then set reviewers and assignees on GitHub in one call.

`$ARGUMENTS` may be a PR number, a PR URL, or empty. Empty means the PR for the current branch.

## The roster

| # | Name | GitHub |
|---|---|---|
| 1 | Jason Godinez | `LmJaredG` |
| 2 | Noah Henry | `NoahHenry481` |
| 3 | Jason Cordis | `jasoncordis0` |
| 4 | Daniel Gazaneo | `danielnaoexiste` |
| 5 | Andrii Ievtukhov | `av-andrii-ievtukhov` |

These are the only people to assign. If the user names someone who is not here, say so and stop rather than guessing at a handle — a wrong login is a public mis-assignment, and `av-andrii-ievtukhov` shows that the handles are not derivable from the names.

## Step 1: Identify the PR

```bash
gh pr view $ARGUMENTS --json number,title,url,state,isDraft,author,reviewRequests,assignees,reviews \
  --jq '{number, title, url, state, draft: .isDraft, author: .author.login, reviewers: [.reviewRequests[]?.login], assignees: [.assignees[]?.login], reviewed: [.reviews[]?.author.login] | unique}'
```

Stop if the PR is merged or closed, or if the current branch has no PR — say so rather than reaching for a different PR.

A draft PR is fine to assign, but say it is a draft when you present it: a review request on a draft does not notify the way an open one does.

## Step 2: Ask who

Present the PR (number, title, one line on what it changes) and then the roster as a numbered list, with these people already dropped or marked:

- **The PR author.** GitHub refuses a review request from the author of the PR, so leave them out of the choices entirely.
- **Anyone already requested or already assigned.** Keep them in the list but mark them `(already on)`, so the user can see the current state and re-add deliberately.
- **Anyone who has already submitted a review.** Mark them `(reviewed)`. Adding them again is a genuine re-request, not a no-op — do it only when asked.

Then ask, in one message:

1. **Who?** By number, by name, or "all".
2. **As reviewers, assignees, or both?** Reviewers is the usual answer; say so as the default.

Wait for the reply. Ask as plain text, not with the question tool — that tool caps a question at four options and the roster is five people.

If the user's original request already named the people and the role, skip the ask and go to Step 3; the Step 4 report is where they confirm.

## Step 3: Apply

One `gh pr edit` for the whole set, repeating the flag per login rather than comma-joining:

```bash
gh pr edit <number> \
  --add-reviewer NoahHenry481 --add-reviewer jasoncordis0 \
  --add-assignee danielnaoexiste
```

Reviewer and assignee are separate fields: requesting a review does not assign anyone, and assigning does not request a review. "Both" means passing both flags for the same login.

Failures worth reading rather than retrying:

- `Reviews may only be requested from collaborators` — that login has no access to this repo. Report which one; someone has to be added to the repo before this can work.
- `Could not resolve to a User` — the handle is wrong or the account is gone. Report it; do not try variations.

A partial failure leaves the earlier flags applied, so re-read the PR in Step 4 rather than assuming the command's exit code describes the whole set.

## Step 4: Report

Re-read the PR with the Step 1 query and report what is actually on it now:

- Reviewers requested, and assignees set
- Anyone who was asked for but did not land, with the error
- The PR URL

State the end state, not the command that was run.
