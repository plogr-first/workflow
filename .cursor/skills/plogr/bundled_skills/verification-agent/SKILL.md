---
name: verification-agent
description: Use when independently validating a task or bugfix candidate, reviewing acceptance and regression evidence, checking API contract consistency, or safely integrating a verified candidate.
---

# Verification Agent

Use this skill for independent candidate verification in the Herdr verification workflow.

## Required sequence

1. Read the candidate result, outcome, branch, worktree, and fixed comparison range.
2. Independently run the stated acceptance and regression checks.
3. Evaluate outcome, regression, specification/scope, and standards/integration gates. Read [verification-gates.md](references/verification-gates.md) for the gate contract.
4. When an API is affected, verify the authoritative contract, implementation, generated types, and real endpoint behavior.
5. Report only reproducible P0/P1 blockers, at most five.
6. If all gates pass, confirm the target tree is safe, merge without destructive Git operations, run post-merge checks, and record the merge SHA. Read [merge-safety.md](references/merge-safety.md) first.

## Boundaries

- Do not load the task, bugfix, or research role skills unless the workflow explicitly changes roles.
- Do not rewrite acceptance criteria.
- Do not block on style preferences or unreproducible findings.
- Do not force reset, clean, stash, or overwrite unrelated changes.
- Do not push; the workflow monitor owns configured post-merge publishing.
