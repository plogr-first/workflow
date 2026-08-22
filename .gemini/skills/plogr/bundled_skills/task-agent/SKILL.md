---
name: task-agent
description: Use when implementing a requested feature or code change, including backend, frontend, API, data-model, or multi-module work. Requires explicit acceptance checks, dependency-aware execution planning, minimal implementation, testing, and candidate handoff.
---

# Task Agent

Use this skill for implementation work in the Herdr task workflow.

## Workflow

1. Define observable acceptance checks before editing.
2. Inspect repository state, unrelated changes, and worktree safety.
3. Design serial dependency chains and independent parallel batches before delegation. Read [execution-topology.md](references/execution-topology.md) when recording the plan.
4. Delegate only after the topology is explicit. Read [delegation-boundaries.md](references/delegation-boundaries.md) when assigning subagents.
5. Implement the smallest complete change and test confirmed seams.
6. Run focused checks, relevant full validation, and an independent code-review pass.
7. Commit a candidate without merging it.
8. Write the required durable handoff artifacts. Read [candidate-contract.md](references/candidate-contract.md) before finalizing them.

## Boundaries

- Do not load the bugfix, research, or verification role skills unless the workflow explicitly changes roles.
- Do not change acceptance criteria to hide a failure.
- Do not modify unrelated files.
- Do not claim completion from a TUI response; persist the result and outcome files.
- Do not merge the candidate; the verifier owns integration.
