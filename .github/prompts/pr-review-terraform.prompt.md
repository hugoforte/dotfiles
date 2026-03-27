---
agent: agent
description: You are helping me review a pull request that changes Terraform infrastructure code. Follow this workflow:'
---

### Step 1: Find Relevant PRs

Find all open PRs. Highlight ones where I am assigned or requested as a reviewer:

```bash
gh pr list \
  --state open \
  --limit 20 \
  --json number,title,author,reviewRequests,assignees,createdAt \
  --jq '.[] | {number, title, author: .author.login, reviewers: [.reviewRequests[]?.login], assignees: [.assignees[]?.login], created: .createdAt}'
````

If there are multiple PRs, ask which one I want to review. Present the results to me as a numbered list for me to choose from, clearly marking the ones requiring my attention. If there's only one, confirm before proceeding.

### Step 2: Check Out and Examine the PR

Once I confirm the PR:

1. Check out the PR locally: `gh pr checkout <PR_NUMBER>`
2. Get PR details: `gh pr view <PR_NUMBER>`
3. Get the full diff against the base branch: `gh pr diff <PR_NUMBER>`
4. Check for existing review comments: `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments`

Also gather Terraform context (best effort):

* Identify Terraform root modules (folders containing `*.tf` and typically a `backend`/providers/variables).
* Identify environments/workspaces (`env/`, `environments/`, `live/`, `prod/`, `staging/`, etc.).
* Identify module boundaries (`modules/`), provider(s), and backend configuration.

### Step 3: Analyze the Changes

Examine the diff and provide:

**High-Level Summary**

* What is the overall purpose of this PR?
* New/changed resources (by provider + resource type)
* New/changed modules (new module, module version bump, module ref change)
* Provider changes (new providers, version changes, alias usage changes)
* Backend/state changes (backend type, bucket/key/table, workspace usage)
* Variable/interface changes (new vars, removed vars, changed defaults, validation changes)
* Output changes (new outputs, removed outputs, sensitive outputs)
* Any breaking changes (renames, address moves, force-recreate, state moves implied)

**Plan & Apply Risk Check**

* Does this PR include plan output? If not, recommend adding a plan for each affected environment.
* Identify destructive operations risk:

  * `- destroy` or `-/+ replace` resources
  * Anything that looks like “rename without state mv”
  * Changes to IAM, networking, KMS, data stores, or production-critical resources
* Identify drift risk:

  * Changes to data sources that might fetch different values at apply-time
  * Use of `latest`/unpinned versions
  * Implicit defaults changing (provider upgrades, module upgrades)

**State Safety**

* Flag any backend config changes as high-risk.
* Check for:

  * Remote backend, locking (e.g., DynamoDB / Cloud Storage locking where applicable)
  * State key naming conventions and uniqueness per env
  * Avoiding local state in shared repos
* If resource addresses are changing (rename/module path change), look for evidence of `terraform state mv` plan or `moved {}` blocks (Terraform 1.1+).

**Security & Least Privilege**

* IAM changes: broad principals (`*`), wide actions (`*`), admin roles, wildcard resources.
* Secrets handling:

  * No plaintext secrets in variables, locals, tfvars, or outputs
  * Use secret managers / references where appropriate
  * Mark outputs `sensitive = true` where needed
* Network exposure:

  * Public ingress/egress rules
  * Open security groups / firewall rules (0.0.0.0/0, ::/0)
  * Public buckets, public endpoints, permissive ACLs/policies
* Encryption:

  * Storage encryption enabled (KMS where required)
  * Database/storage encryption at rest & in transit

**Reliability / Operations**

* Tagging/labels: required tags present (owner, env, cost-center, data-classification, etc. as applicable)
* Logging/monitoring:

  * CloudTrail/audit logs, flow logs, log retention
  * Alerts where new critical infra is created
* HA/DR considerations for stateful services

**Terraform Hygiene**

* Versions pinned:

  * `required_version` in `terraform {}` (avoid unbounded)
  * `required_providers` with constrained versions
  * Module sources pinned (avoid floating git branches; prefer tags/SHAs)
* Formatting and structure:

  * `terraform fmt` expected
  * Clear naming conventions
  * Avoid excessive `count`/`for_each` complexity without comments
* Linting/testing:

  * Suggest `tflint`, `tfsec`/`trivy`, `checkov` if used in repo
  * Suggest `terraform validate` and `terraform plan`

### Step 4: Review Focus Areas

Provide a numbered list of files or directories to review, in logical order (foundational changes first, then modules, then env roots, then docs/tests). For each item, briefly note what to focus on:

* Provider/backend/version constraints and lockfile changes
* Module source/version changes and module interface changes
* Resource changes with high blast radius (IAM, network, KMS, stateful services)
* Any `moved {}` blocks / renames / address changes
* Variables/outputs changes (especially `sensitive`)
* Tagging/labels consistency
* Any unusual use of `depends_on`, `ignore_changes`, `lifecycle { prevent_destroy = ... }`
* Any `null_resource` / provisioner usage (flag strongly; prefer native resources)
* Test/validation evidence: plan outputs, CI checks, and environment coverage
* Documentation updates: README, runbooks, environment notes

### Step 5: Suggested Comments

Prepare a list of suggested review comments. For each comment:

* Keep it short and to the point
* Use a friendly, suggestion-based tone (e.g., "Consider...", "Might be worth...", "Nit: ...")
* Only be strongly opinionated if there's an obvious bug or issue
* Include the file path and line number
* **Verify line numbers** by reading the actual file content before suggesting

Terraform-specific comment types to prioritize:

* Missing version pinning (`required_version`, provider constraints, module pins)
* Risky destroys/replacements without migration plan
* IAM wildcards or public access paths
* Plaintext secrets or non-sensitive outputs
* Backend/state safety issues
* Missing tags/labels
* Missing plan evidence for affected envs

Format each suggestion as:

```
File: <path>
Line: <number>
Comment: <your suggestion>
```

### Step 6: Generate Review JSON

First, generate the `review.json` file for the user to review. Do NOT submit it yet.

1. **Get the Commit SHA:**

   ```bash
   COMMIT_SHA=$(gh pr view <PR_NUMBER> --json headRefOid -q .headRefOid)
   ```

2. **Check for Existing Pending Reviews:**

   GitHub allows only ONE pending review per user per PR. Check first:

   ```bash
   gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews | jq '.[] | select(.state == "PENDING")'
   ```

   If a pending review exists, ask user if they want to delete it or add to it via UI.
   To delete: `gh api -X DELETE repos/{owner}/{repo}/pulls/{pr_number}/reviews/{REVIEW_ID}`

3. **Generate the JSON Payload:**

   Create a file named `review.json` with the following structure.

   **IMPORTANT**:

   * Do NOT include the `event` field - this creates a PENDING review
   * Use `line` and `side` for inline comments (NOT `position`)
   * `line`: The line number in the file (1-based)
   * `side`: "RIGHT" for new/modified code, "LEFT" for old code
   * Only lines visible in the PR diff can receive comments
   * For general feedback, use the review `body` field, but keep this very short - one or two sentences max.
   * Never use the body for inline comments - use the comments array instead

   ```json
   {
     "commit_id": "REPLACE_WITH_COMMIT_SHA",
     "body": "Brief review summary (1-2 sentences max)",
     "comments": [
       {
         "path": "path/to/file",
         "line": 42,
         "side": "RIGHT",
         "body": "Your comment here"
       }
     ]
   }
   ```

   **Note**: Always use actual line numbers from the file, not diff positions. Verify line numbers by reading the file content before creating comments.

### Step 7: Validate and Create Pending Review

**First, validate the JSON structure:**

```bash
$review = Get-Content review.json | ConvertFrom-Json
Write-Host "✅ JSON is valid with $($review.comments.Count) inline comments ready for submission"
```

If validation succeeds, create the pending review:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --method POST --input review.json
```

This will return a review ID. Save it for the next step.

**Common Errors and Solutions:**

1. **"User can only have one pending review per pull request"**

   * Delete existing pending review first (see Step 6)
   * Or ask user to add comments via GitHub UI

2. **"Position could not be resolved, Line could not be resolved"**

   * Solution: Always use `line`/`side` format, never `position`
   * Verify line numbers by reading the actual file
   * Only comment on lines visible in the PR diff

3. **"Problems parsing JSON"**

   * Check for unescaped quotes in comment bodies
   * Verify JSON is valid using `Get-Content review.json | ConvertFrom-Json`

This creates a **PENDING** review visible in GitHub UI.

### Step 8: Submit the Pending Review

Once user approves, submit the review. Choose event type based on findings:

**Request Changes (has critical issues):**

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews/{REVIEW_ID}/events --method POST -f event=REQUEST_CHANGES
```

**Approve (looks good):**

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews/{REVIEW_ID}/events --method POST -f event=APPROVE
```

**Comment only (minor suggestions):**

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews/{REVIEW_ID}/events --method POST -f event=COMMENT
```

The review will be immediately published and visible to all PR participants.

### Output Format

Present your findings in sections, then wait for my feedback. I will:

* Ask you to modify suggestions
* Tell you which comments to keep/remove
* Request changes to the review approach

Do NOT submit any reviews or comments until I explicitly approve the plan.

```
```
