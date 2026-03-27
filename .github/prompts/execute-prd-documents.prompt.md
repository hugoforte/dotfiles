---
agent: agent
---

## 0) Configuration (Fill These In)

### Project Context
- **PRD Document**: `[PATH_TO_PRD]` - ask for this
- **Tasks Document**: `[PATH_TO_TASKS]` *(recommended; see §1.2 if missing)*

### Execution Mode
Choose exactly one:
- **MODE=guided** → stop after every task
- **MODE=phase** → stop after every phase *(default)*
- **MODE=batch:N** → stop every N tasks (e.g., batch:5)
- **MODE=autopilot** → proceed until a mandatory checkpoint

**Phase definition (for MODE=phase):**
- A **Phase** is a top-level heading in the **Tasks document** (e.g., `## Phase 2: API`).
- All tasks listed under that heading (until the next top-level heading) are part of that phase.

Set here:
- **MODE**: `phase`

### Project Commands (Fill In Once)
Provide the canonical commands for this repo. The agent should prefer targeted commands when possible.

If the agent cannot execute commands directly, it must output these commands verbatim for the user to run.
- **Install**: `[e.g., pnpm i]`
- **Lint**: `[e.g., pnpm lint]`
- **Unit tests**: `[e.g., pnpm test]`
- **Integration tests**: `[e.g., pnpm test:integration]` *(if applicable)*
- **E2E tests**: `[e.g., pnpm test:e2e]` *(if applicable)*

---

## 1) Preconditions

### 1.1 Required inputs
The agent MUST have:
1. **PRD** with: problem statement, requirements (functional/non-functional), API contracts (if any), success criteria.
2. **Tasks list** (recommended) with: granular checklist items, file references, test scenarios.

### 1.2 If Tasks document is missing
If no Tasks document exists, the agent MUST STOP and do one of the following:
- Ask the user for a Tasks document, **or**
- Propose a minimal Tasks checklist derived from the PRD, and ask the user to approve it before coding.

### 1.3 Mandatory PRD Extraction (do this once before coding)
Before implementing any task, the agent MUST read the PRD and produce a short, structured extraction:
- **Objective**: one sentence
- **Success criteria**: bullet list (verbatim or near-verbatim)
- **API/contract changes**: endpoints/interfaces/events affected (if any)
- **Non-functional constraints**: performance, security, reliability, backwards compatibility
- **Out of scope**: explicit non-goals from PRD (or inferred exclusions if stated)

If any of the above are unclear in the PRD, the agent MUST STOP and ask for clarification before coding.

---

## 2) Source-of-Truth Hierarchy

1. **PRD** (highest priority)
2. **Existing code + platform constraints** (what actually compiles/runs)
3. **Tasks document** (implementation plan)
4. **Agent suggestions** (lowest priority)

If the Tasks document conflicts with the PRD, the agent MUST STOP and report the conflict.

---

## 3) Scope & Task Boundaries

### 3.1 Incremental execution contract
For EACH task, the agent MUST:
1. Read the next uncompleted task (from Tasks doc / tracker)
2. Read PRD sections relevant to this task
3. Implement ONLY this task (see allowed supporting work)
4. Run relevant tests
5. Update progress tracking
6. Report completion
7. Stop per MODE

### 3.2 Allowed supporting work (to keep reality from breaking the agent)
Allowed when necessary to complete the current task:
- Small refactors required to compile / pass tests
- Fixing types, imports, lint errors caused by the change
- Adding tiny helpers/utilities strictly needed for the task

Not allowed:
- Implementing user-visible behavior that belongs to a future task
- Large refactors “while we’re here”
- Expanding requirements beyond the PRD

---

## 4) Testing Rules

### Per-task
- Run the smallest relevant test set for the touched area (targeted unit tests, single test file, etc.).
- Run lint/format if available.

### Per-phase
- Run the full unit test suite (and integration if phase scope touches integration boundaries).

### Final
- Run full suite as defined in PRD (unit + integration + e2e).

If tests fail:
- Perform **one** triage pass (identify failing test/error, locate likely cause, attempt one minimal fix).
- If still failing, STOP and report using the blocker template.

---

## 5) Mandatory Checkpoints (Always Stop)

The agent MUST STOP and request guidance/approval when:
1. An architectural decision is required
2. A blocker remains after one triage pass
3. PRD and Tasks conflict
4. A phase is complete (MODE=phase)
5. All implementation tasks are complete (before final full-suite testing)
6. Final validation is complete (before declaring done)

---

## 6) Progress Tracking

Preferred: update the **Tasks document in-repo** by marking tasks complete.

### Tasks document format expectation
- Use Markdown checkboxes (`- [ ]` / `- [x]`) for tasks.
- Group tasks into phases with headings.
- Each task should be small enough to complete + test in one iteration.

If the Tasks document is not editable in this environment (rare for Copilot):
- Maintain a **Progress Ledger** in chat output with checkboxes and task counts.

---

## 7) Git Hygiene (Repo Safety)

- Keep changes minimal and scoped to the current task.
- Prefer small, reviewable commits **when the environment supports it**.
- Before reporting completion, the agent should quickly review `git diff` (or equivalent) to verify no unrelated changes.
- Do not reformat or rename files unless required for the current task.

---

## 8) Reporting Templates

### 7.1 Task Completion Report

```markdown
## Task Completion Report

✅ **Task Completed**: [Exact task name]

📝 **Changes Made**:
- File: [path] — [what changed]

🧪 **Tests**:
- Unit tests: [✅ Passing / ❌ Failing / ⏭️ Not run]
- Integration tests: [✅ Passing / ❌ Failing / ⏭️ Not run]
- E2E tests: [✅ Passing / ❌ Failing / ⏭️ Not run]

🧠 **Notes/Decisions**: [None / short note]

📋 **Progress**: [X/Y tasks complete in current phase]

⏭️ **Next**: [Next task name]

---
🛑 **STOPPING FOR APPROVAL** (per MODE)
```

### 7.2 Phase Completion Report

```markdown
## Phase Completion Report

✅ **Phase**: [Phase name]
📊 **Tasks Completed**: [X/Y]

📝 **Summary**:
- [What shipped in this phase]
- [Key files touched]

🧪 **Test Status**:
- Unit: [✅/❌]
- Integration: [✅/❌/N/A]

⚠️ **Risks/Notes**:
- [Any follow-ups]

---
🛑 **PHASE COMPLETE — WAITING FOR APPROVAL**
```

### 7.3 Blocker Report

```markdown
## 🚨 Blocker Encountered

**Task**: [Current task]
**Issue**: [Exact error / failing test / missing dependency]
**Context**: [What the agent was doing]
**Files Involved**: [paths]
**Triage Performed**: [what was checked / one attempted fix]

---
**Request**: Please advise how to proceed.
```

### 7.4 Architectural Decision Needed

```markdown
## 🧭 Architectural Decision Needed

**Decision**: [What must be decided]

**Options**:
1. [Option A] — Pros/cons
2. [Option B] — Pros/cons

**Recommendation**: [What the agent suggests and why]

---
**Request**: Choose an option (or provide another).
```

---

## 9) Quality Gates

Before declaring complete:
- [ ] All Tasks are checked off (or ledger matches)
- [ ] PRD success criteria validated one-by-one
- [ ] Full test suite passes (as defined in PRD)
- [ ] Docs updated (API docs/migration notes if breaking changes)
- [ ] No TODOs / placeholders remain

---

## 10) Notes for “Generic-ness”

### Copilot-friendly operating tips (generic)
- Prefer editing the smallest number of files necessary.
- When unsure about repo conventions, search for nearby patterns in existing code.
- Keep terminal output snippets in reports when they are important (failing tests, migrations, build errors).



- Do NOT embed feature-specific endpoints, file paths, or framework code samples in this contract.
- Put framework-specific patterns in a separate appendix if needed.

---

**Document Version**: 1.1 (Working Draft)
**Last Updated**: January 22, 2026

