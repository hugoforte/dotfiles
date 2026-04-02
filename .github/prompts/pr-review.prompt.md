---
mode: agent
description: Review pull requests with structured analysis and suggested review comments
---

### 0 Step 1: Find Relevant PRs

Find open PRs where I am assigned, requested as a reviewer, or have already submitted a review:

```bash
gh pr list \
  --search "is:open (review-requested:@me OR reviewed-by:@me OR assignee:@me)" \
  --limit 10 \
  --json number,title,author,reviewRequests,assignees,createdAt \
  --jq '.[] | {number, title, author: .author.login, reviewers: [.reviewRequests[]?.login], assignees: [.assignees[]?.login], created: .createdAt}'
```

If there are multiple PRs, ask which one I want to review. Present the results to me as a numbered list for me to choose from. If there's only one, confirm before proceeding.

### Step 2: Check Out and Examine the PR

Once I confirm the PR:

1. Check out the PR locally: `gh pr checkout <PR_NUMBER>`
2. Get PR details: `gh pr view <PR_NUMBER>`
3. Get the full diff against the base branch: `gh pr diff <PR_NUMBER>`
4. Check for existing review comments: `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments`

### Step 3: Discover Standards and Analyze Changes

Before analysis, load coding standards dynamically so this prompt works across repositories:

1. Load repo-wide instruction files if present:
   - `.github/copilot-instructions.md`
   - `AGENTS.md`
   - `COPILOT_INSTRUCTIONS.md`
2. Discover instruction files under `.github/instructions/` (including subfolders).
3. For each instruction file, read frontmatter and extract `applyTo` patterns (single pattern or comma-separated list).
4. Match changed files from Step 2 against those patterns.
5. Build a per-file instruction set and apply all matching instruction files for each file.
6. If an instruction file has no `applyTo`, treat it as global guidance.
7. If no instruction files are found, continue with repo-wide instructions and this prompt's review criteria.

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
- Look for existing libraries in the codebase that could be used instead (check imports across the codebase)

**Impact Assessment**

- How does this affect existing code?
- What areas of the codebase will need to be aware of these changes?
- Are there documentation implications?

### Step 4: Review Focus Areas

Provide a numbered list of files or directories to review, in logical order (foundational changes first, then core logic, then usages, then tests). For each item, briefly note what to focus on:

- API or DB schema design considerations, if any
- Complex logic that needs careful examination
- Potential edge cases or error handling gaps
- Performance considerations
- Security implications
- Test coverage gaps
- Code style or consistency issues

### Step 5: Suggested Comments

Prepare a list of suggested review comments. For each comment:

- Keep it short and to the point
- Use a friendly, suggestion-based tone (e.g., "Consider...", "Might be worth...", "Nit: ...")
- Only be strongly opinionated if there's an obvious bug or issue
- Include the file path and line number
- **Verify line numbers** by reading the actual file content before suggesting

Format each suggestion as:

```
File: <path>
Line: <number>
Comment: <your suggestion>
```

### Output Format

Present your findings in sections, then wait for my feedback. I will:

- Ask you to modify suggestions
- Tell you which comments to keep/remove
- Request changes to the review approach

Do NOT submit any reviews or comments
