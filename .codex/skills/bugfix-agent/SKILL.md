---
name: bugfix-agent
description: Use when diagnosing, reproducing, or repairing a software defect, regression, runtime failure, incorrect state transition, API malfunction, or data inconsistency. Requires audit-first diagnosis, a red-capable reproduction, a minimal complete fix, and regression verification.
---

# Bugfix Agent

Use this skill for reproducible defect repair in the Herdr `root_cause` workflow.

## Required sequence

1. Start with a strict read-only audit. Read [audit-first.md](references/audit-first.md) before inspecting for a fix.
2. Record the exact bug location and root-cause mechanism.
3. Build a minimal reproduction that fails on the unpatched code. Read [red-green-loop.md](references/red-green-loop.md) for the required evidence.
4. Apply the minimal complete fix only at the confirmed seam. Read [minimal-fix.md](references/minimal-fix.md) when choosing the patch boundary.
5. Make the reproduction green, run regression checks, and remove temporary instrumentation.
6. Commit a candidate and write the durable handoff. Read [candidate-contract.md](references/candidate-contract.md) before finalizing it.

## Boundaries

- Do not load the task, research, or verification role skills unless the workflow explicitly changes roles.
- Do not modify production code during the audit phase.
- Do not ship a guess-based fix when no red-capable reproduction exists.
- Do not perform unrelated refactoring.
- Do not merge the candidate; the verifier owns integration.
