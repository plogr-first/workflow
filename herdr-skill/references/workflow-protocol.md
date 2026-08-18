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

## Research

Use `Mode research`.

Execution: define scope/freshness/decision; use primary sources; build a claim ledger with source, exact evidence, access date, and confidence; record contrary evidence and uncertainty; remain read-only.

Verification: audit every decision-critical claim for source provenance, evidence match, and scope coverage. `passed` requires first-party evidence or explicit uncertainty for every critical claim. `fix_required` is only for missing or mismatched evidence, not prose quality.

## Task

Use `Mode task`.

Execution: define observable acceptance checks; inspect Git status/current branch/worktrees/concurrent edits; isolate in a worktree when shared tree is dirty, concurrent, or overlapping; implement the smallest complete change; run focused and relevant full checks; commit a `candidate`. Record worktree path, branch, base SHA, candidate SHA, changed files, and command results. Do not merge.

Verification gates:

1. Outcome: stated acceptance checks pass.
2. Regression: relevant automated checks pass; changed behaviour has a meaningful regression check or documented lack of a valid seam.
3. Spec/scope: requirements are complete and no unrequested scope expansion exists.
4. Standards/integration: repository rules pass and no reproducible P0/P1 review finding remains.
5. API contract, when API-affecting: authoritative docs/OpenAPI, backend route/controller/validation, generated client/types, and actual endpoint/integration behaviour agree on method, path, auth, fields, status/error semantics, and pagination/cursor semantics.

On pass, verifier confirms target tree is clean and at expected base, merges safely, runs applicable post-merge verification, records merge SHA, and emits `merged`. Never force reset, clean, stash, or overwrite unrelated changes.

## Bugfix

Use `Mode bugfix`.

Execution must first build and run a narrow, red-capable reproduction for the reported symptom. Minimise it, test falsifiable hypotheses one variable at a time, add a regression test at the correct seam where possible, fix root cause, rerun original reproduction, remove temporary instrumentation, commit `candidate`. If no red-capable loop exists, emit `blocked`; do not ship a guess-based patch.

Verification independently reruns original reproduction and regression check, confirms debug cleanup, then applies task gates 1–5 and merges only after pass.

## Verifier findings and repair

A verifier reports only reproducible P0/P1 blockers, maximum five. Every item states acceptance gate, file/command evidence, and smallest required repair. It must not block on style preferences or findings already enforced by tooling. The controller reuses the same execution Agent and worktree for at most two repairs.

## Durable resume and session identity

`herdr init` binds a project profile to one named Herdr session. Every formal `workflow.json` records that session, a unique workflow ID, task/verifier Agent names, current role, and repair round. `herdr resume` only considers unfinished workflows in the bound project/session. It reads `events.jsonl`, handoff files, progress files, and Git/worktree state; it never infers identity from a pane title or chat history. If the recorded Agent is gone, it starts a replacement generation and updates the workflow state before continuing. Multiple resumable workflows require an explicit workflow ID or `--all`. Terminal states are never reactivated.

The task role uses the available mattpocock implementation/debugging skill; verification uses the available review/QA and API-contract checks. A missing required skill must be recorded as a blocker, not silently treated as a successful review.
