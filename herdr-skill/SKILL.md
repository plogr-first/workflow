---
name: herdr
description: "Use when the user explicitly invokes /herdr or asks to launch, coordinate, receive results from, or repair agents through Herdr. Dispatches durable research, task, and bugfix workflows with project profiles, worktrees, independent verification, bounded repair, API-contract checks, and safe integration."
---

# /herdr

## Entry

- Use this Skill only for an explicit Herdr request.
- For dispatch, require `HERDR_ENV=1`. `herdr init` is the only exception.
- Read `<project>/herdr/dispatch-profile.json` once. If absent, tell the user to run `herdr init` in that project; do not install wrappers, modify PATH, or run `npx` yourself.
- Do not pre-run `herdr agent`, pane commands, `opencode models`, or inspect launcher source. The scripts do that when needed.
- Do not hand-build pane IDs or invoke `herdr agent prompt` to advance a formal workflow.

## Dispatch

For every formal research, task, or bugfix request, construct a brief containing: goal, scope/forbidden changes, observable acceptance checks, relevant paths/commands, and no secrets. Then run exactly one workflow launcher:

```powershell
& '<herdr-skill-root>\scripts\Start-HerdrWorkflow.ps1' `
  -Mode <research|task|bugfix> -Slug <lowercase-slug> -Prompt '<brief>'
```

Use `Start-HerdrAgent.ps1` only for a one-off Agent operation that does not require workflow verification, repair, or integration.

## Resume

After a Herdr or computer restart, run `herdr resume` from the project root inside a Herdr-managed pane. The project profile binds workflows to one named Herdr session; the resume controller scans only that session and project. If more than one workflow is resumable, it lists them; resume one explicitly with `herdr resume <workflow-id>` or intentionally use `herdr resume --all`.

`herdr --session <name> resume [workflow-id]` is equivalent but rejects a session that differs from the project binding.

Resume reads persisted `workflow.json`, `events.jsonl`, handoffs, Git/worktree state, and the configured mattpocock skill manifest. It wakes the persisted `next_role` (`task` or `verification`), starts a replacement Agent when the recorded Agent is gone, and never guesses across sessions. It must not resume terminal `merged`, `passed`, or `blocked` workflows.

- `research`: use the research profile; require primary evidence and read-only work.
- `task`: use the task profile; require implementation, candidate commit, and acceptance checks.
- `bugfix`: use the task profile; require a red-capable reproduction before a fix.

## Workflow contract

The workflow launcher starts execution and deferred verification Agents, then the monitor wakes the next role from machine state. Do not manually start a second verifier.

- Execution/research Agent writes its own `result.md` and valid `outcome.json`.
- Verification Agent writes its own `result.md`, `outcome.json`, and independent `verification.md` when applicable.
- Monitor alone writes `workflow.json` and may issue at most two repair prompts to the original execution Agent.
- Verifier reports only reproducible P0/P1 blockers, maximum five. Third unresolved verification, unsafe merge, or unreproducible bug is `blocked`.
- Task/bugfix succeeds only at `merged`: all protocol gates pass, merge is safe, and post-merge checks pass. Research succeeds only at `passed`.
- API-affecting task/bugfix verification must include the API-contract gate.

Read [workflow protocol](references/workflow-protocol.md) before writing a brief or interpreting an outcome. On explicit script failure, read [troubleshooting](references/troubleshooting.md). Read [setup/runtime](references/setup-runtime.md) only for `herdr init`, wrappers, profiles, or model selection.

## Completion

Read final `workflow.json`, execution result, and verification result. Report success only for `merged` or `passed`; otherwise report the final state, exact blocker, and handoff paths. Do not expose credentials in briefs, results, or notifications.
