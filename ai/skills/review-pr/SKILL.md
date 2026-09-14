---
name: review-pr
description: Review a pull request with structured analysis and suggested review comments. Use when asked to review a PR or to find PRs waiting on my review.
---


## Step 1: Find Relevant PRs

Find open PRs where I am assigned, requested as a reviewer, or have already submitted a review:

```bash
gh pr list \
  --search "is:open (review-requested:@me OR reviewed-by:@me OR assignee:@me)" \
  --limit 10 \
  --json number,title,author,reviewRequests,assignees,createdAt \
  --jq '.[] | {number, title, author: .author.login, reviewers: [.reviewRequests[]?.login], assignees: [.assignees[]?.login], created: .createdAt}'
```

If there are multiple PRs, ask which one I want to review. Present the results as a numbered list. If there's only one, confirm before proceeding.

If a PR number is provided as an argument (`$ARGUMENTS`), skip this step and use that PR number directly.

## Step 2: Check Out and Examine the PR

Once confirmed:

1. Check out the PR locally: `gh pr checkout <PR_NUMBER>`
2. Get PR details: `gh pr view <PR_NUMBER>`
3. Get the full diff against the base branch: `gh pr diff <PR_NUMBER>`
4. Check for existing review comments: `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments`

## Step 3: Load Standards and Analyze Changes

Before analysis, load the relevant coding standards for changed files:

- **Global**: `CLAUDE.md` and `.github/copilot-instructions.md` apply to all files
- **All Backend C#** (`Backend/**/*.cs`): `.github/instructions/backend.instructions.md`
- **Core layer** (`Backend/0_Core/**/*.cs`): `.github/instructions/backend-core.instructions.md`
- **Infrastructure layer** (`Backend/1_Infrastructure/**/*.cs`): `.github/instructions/backend-infrastructure.instructions.md`
- **Application layer** (`Backend/2_Application/**/*.cs`): `.github/instructions/backend-application.instructions.md`
- **Web/Runtime layer** (`Backend/3_Run/**/*.cs`): `.github/instructions/backend-web.instructions.md`
- **Tests** (`Backend/Tests/**/*.cs`): `.github/instructions/backend-tests.instructions.md`
- **Frontend** (`Frontend/**/*.ts`, `Frontend/**/*.tsx`): `.github/instructions/frontend.instructions.md`
- **Terraform** (`Deploy/**/*.tf`): `.github/instructions/terraform.instructions.md`

Read only the instruction files that match the changed files in the diff. Apply them when reviewing those files.

Then examine the diff and provide:

**High-Level Summary**

- What is the overall purpose of this PR?
- New APIs introduced (endpoints, functions, methods)
- New or modified data structures (types, interfaces, schemas)
- New dependencies or libraries added
- Architectural or design pattern changes
- Configuration changes
- Database migrations or schema changes
- Any breaking changes

**Dependency Check**

- For any new dependencies: check if they are actively maintained
- Flag archived, deprecated, or unmaintained libraries
- Look for existing libraries in the codebase that could be used instead

**Impact Assessment**

- How does this affect existing code?
- What areas of the codebase will need to be aware of these changes?
- Are there documentation implications?

## Step 4: Review Focus Areas

Provide a numbered list of files or directories to review, in logical order (foundational changes first, then core logic, then usages, then tests). For each item, briefly note what to focus on:

- API or DB schema design considerations
- Complex logic that needs careful examination
- Potential edge cases or error handling gaps
- Performance considerations
- Security implications
- Test coverage gaps
- Code style or consistency issues

## Step 5: Suggested Comments

Prepare a list of suggested review comments. For each comment:

- Keep it short and to the point
- Use a friendly, suggestion-based tone ("Consider...", "Might be worth...", "Nit: ...")
- Only be strongly opinionated if there's an obvious bug or security issue
- Include the file path and line number
- **Verify line numbers** by reading the actual file content before suggesting

Format each suggestion as:

```
File: <path>
Line: <number>
Comment: <your suggestion>
```

## Output Format

Present findings in the sections above, then wait for feedback. The user will:

- Ask to modify suggestions
- Tell you which comments to keep/remove
- Request changes to the review approach

**Do NOT submit any reviews or comments to GitHub without explicit instruction.**
