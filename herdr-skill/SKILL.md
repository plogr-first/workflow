---
name: plogr
description: "Dispatch or recover durable Plogr/Herdr research, task, bugfix, and matrix workflows. Use when the user invokes /plogr or /herdr, asks to launch, coordinate, receive results from, or repair Herdr agents."
---

# Plogr workflow orchestrator

## Entry

- Use this skill for `/plogr` and `/herdr`.
- Require `HERDR_ENV=1` for dispatch. The initializer is the only exception.
 - Read `<project>/herdr/dispatch-profile.json` once. If missing, tell the user to run `plogr init`; do not create wrappers or guess a profile.
- Do not hand-build panes, advance agents with manual prompts, or start a second verifier.

## Dispatch

Create one brief with goal, scope and forbidden changes, observable acceptance checks, relevant paths/commands, and no secrets. Launch exactly one workflow:

```powershell
& '<herdr-skill-root>\scripts\Start-HerdrWorkflow.ps1' `
  -Mode <research|task|bugfix> -Slug <lowercase-slug> -Prompt '<brief>'
```

Use `Start-HerdrParallelWorkflow.ps1` only for a documented matrix of independent scopes. Use `Start-HerdrAgent.ps1` only for a one-off operation without formal verification or integration.

## Required behavior

- Research is read-only and evidence-led.
- Task execution uses the mandatory subagent-driven topology defined in [workflow-protocol.md](references/workflow-protocol.md).
- Bugfix begins with the registered project `audit-suite` skill in strict read-only mode, then a red-capable reproduction, then the minimal complete fix.
- Agents own only their handoff artifacts. The monitor alone owns `workflow.json` and controls repair prompts.
- Success is `merged` for task/bugfix or `passed` for research. Never report a candidate, UI reply, or HTTP success as completion.
- Required skills must exist in `.agents/project-skills.json`; absence is a blocker.

## GitHub and publication

- Use `gh` for GitHub authentication, PR/issue operations, and CI inspection.
- Use Git for local commits, worktrees, branch objects, and the required branch push. `create_pr` pushes the feature branch, then invokes `gh pr create`.
- A publication failure is `push_failed`, never a false `merged` publication result and never a target-branch fallback.

## Resume and completion

Use `herdr resume` only from the bound project/session. It may restart the persisted next role, but never resumes terminal states. At completion, read `workflow.json`, result, and verification artifacts; report the final state, evidence, and handoff paths.

Read [workflow-protocol.md](references/workflow-protocol.md) for role ownership, gates, repair limits, and resume semantics. Read [dispatch-workflows.md](references/dispatch-workflows.md) for matrix dispatch. Read [troubleshooting.md](references/troubleshooting.md) only when startup or launcher recovery is needed.
