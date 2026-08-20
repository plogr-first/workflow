# Herdr workflow protocol

## Roles and state ownership

Each Agent owns only files in its own handoff folder:

- Execution/research Agent: `result.md`, `outcome.json`.
- Verification Agent: `result.md`, `outcome.json`, and `verification.md` when it performs independent acceptance.
- Monitor: the workflow folder's `workflow.json`; Agents never write it.

`outcome.json` must be valid JSON:

```json
{"state":"candidate|passed|fix_required|blocked|merged","summary":"evidence-backed summary"}
```

The monitor reads execution outcome, prompts the deferred verifier, reads verifier outcome, and either prompts the original execution Agent for repair or records the final state. It permits two repair rounds; a third unresolved verification is `blocked`.

The monitor rejects a candidate without a non-empty `result.md`. For task/bugfix candidates it also requires `worktree_decision`, `worktree_path`, `branch`, `base_sha`, and `candidate_sha`. It rejects verifier terminal outcomes without non-empty `result.md` and `verification.md`. A natural-language completion message never substitutes for these files.

## Research

Use `Mode research`.

Execution: define scope/freshness/decision; use primary sources; build a claim ledger with source, exact evidence, access date, and confidence; record contrary evidence and uncertainty; remain read-only.

Verification: audit every decision-critical claim for source provenance, evidence match, and scope coverage. `passed` requires first-party evidence or explicit uncertainty for every critical claim. `fix_required` is only for missing or mismatched evidence, not prose quality.

## Task

Use `Mode task`.

**Subagent-Driven Development Mode (Mandatory)**: Task Execution Agents must operate as lead orchestrators using subagent-driven development. Rather than executing a monolithic implementation in a single context, the primary Task Agent decomposes complex requirements into discrete work packages (e.g. schema/API design, core domain logic, data adapter, integration tests) and delegates them to focused subagents. The primary Task Agent orchestrates subagent deliverables, enforces interface consistency, runs unified TDD, and prepares the candidate commit.

Execution: define observable acceptance checks; inspect Git status/current branch/worktrees/concurrent edits; isolate in a worktree when shared tree is dirty, concurrent, or overlapping; implement the smallest complete change; run focused and relevant full checks; commit a `candidate`. Record worktree path, branch, base SHA, candidate SHA, changed files, and command results. Do not merge.

Make the worktree decision from repository state; use Git worktrees directly when isolation is required. `worktree_decision` is mandatory: `isolated` requires the linked worktree path; `in_place` requires an explicit safety reason in `result.md`. An unborn Git repository has no safe baseline for candidate worktrees; write `blocked` rather than silently committing a project-wide baseline.

Verification gates:

1. Outcome: stated acceptance checks pass.
2. Regression: relevant automated checks pass; changed behaviour has a meaningful regression check or documented lack of a valid seam.
3. Spec/scope: requirements are complete and no unrequested scope expansion exists.
4. Standards/integration: repository rules pass and no reproducible P0/P1 review finding remains.
5. API contract, when API-affecting: authoritative docs/OpenAPI, backend route/controller/validation, generated client/types, and actual endpoint/integration behaviour agree on method, path, auth, fields, status/error semantics, and pagination/cursor semantics.

On pass, verifier confirms target tree is clean and at expected base, merges safely, runs applicable post-merge verification, records merge SHA, and emits `merged`. Never force reset, clean, stash, or overwrite unrelated changes.

`npx plogr-workflow` runs `git init` by default only when the project is not already a Git repository. It never creates the first project-wide commit, configures a remote, or publishes code without user direction. It adds `herdr/` and `.worktrees/` to `.gitignore` for a newly initialized repository.

### GitHub Integration & Submission with GitHub CLI (`gh`)

All GitHub interactions (repository lookup, authentication verification, PR creation, CI checks, issue management, and remote publishing) MUST use the official GitHub CLI (`gh`) instead of browser links or raw unauthenticated commands:
- **`push_policy: after_merge`**: The workflow monitor runs `git push <remote> <target-branch>` after a successful local merge, verified through `gh auth status` when target is a GitHub remote.
- **`push_policy: create_pr`**: The workflow monitor uses `gh pr create --repo <remote-url> --base <target-branch> --title <title> --body <body>` to create an authenticated Pull Request on GitHub.
- **CI / Action Inspection**: Verification agents use `gh pr checks` and `gh run list` / `gh run view` to inspect CI pipelines.
- A push/PR failure preserves the merge, records `push_status: failed`, and sends an attention notification; it must never undo the merge.

## Bugfix

Use `Mode bugfix`.

**Audit-First & Root-Cause Pipeline**:
1. **Audit Phase**: The Agent MUST first execute the global `C:\Users\Lenovo\.agents\skills\audit-suite` skill for read-only static analysis, code/API alignment check, and symptom triage to generate an audit report (`.audit/AUDIT-REPORT-*.md` / `FIX-TASK`).
2. **Diagnosis Phase**: Use `mattpocock/diagnosing-bugs` to build and run a narrow, red-capable reproduction for the reported symptom. Minimise it and test falsifiable hypotheses one variable at a time.
3. **Fix & TDD Phase**: Use `mattpocock/implement` and `tdd` to apply the minimal fix at the root cause seam, rerun the original reproduction to confirm green, remove temporary instrumentation, and commit `candidate`. If no red-capable loop exists, emit `blocked`; do not ship a guess-based patch.

Verification independently reruns original reproduction and regression check, confirms debug cleanup, then applies task gates 1–5 and merges only after pass.

## Verifier findings and repair

A verifier reports only reproducible P0/P1 blockers, maximum five. Every item states acceptance gate, file/command evidence, and smallest required repair. It must not block on style preferences or findings already enforced by tooling. The controller reuses the same execution Agent and worktree for at most two repairs.

## Durable resume and session identity

`npx plogr-workflow` binds a project profile to one named Herdr session. Every formal `workflow.json` records that session, a unique workflow ID, task/verifier Agent names, current role, and repair round. `herdr resume` only considers unfinished workflows in the bound project/session. It reads `events.jsonl`, handoff files, progress files, and Git/worktree state; it never infers identity from a pane title or chat history. If the recorded Agent is gone, it starts a replacement generation and updates the workflow state before continuing. Multiple resumable workflows require an explicit workflow ID or `--all`. Terminal states are never reactivated.

Use the official mattpocock engineering skills recorded by `npx plogr-workflow`: research uses `/research`; task execution uses `/implement`, `/tdd` at confirmed seams, then `/code-review`; bugfix uses `/diagnosing-bugs`, `/tdd` where appropriate, then `/code-review`; verification uses `/code-review` against the fixed point `base_sha...candidate_sha`. `/code-review` is independent review, not the merge authority: the verifier separately runs the Herdr acceptance and API-contract gates before integration. A missing required skill is a blocker, never an assumed pass.
