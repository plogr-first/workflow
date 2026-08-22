# FIX TASK — workflow — 2026-08-23

## Approved scope

User selected all findings from `AUDIT-REPORT-workflow-20260823.md`.

## Batch A — Windows compatibility and executable selection

### F-001

- File: `herdr-skill/tests_formal_audit/Run-All-Formal-Tests.ps1`
- Change: make the runner Windows PowerShell 5.1-safe by removing non-ASCII display glyphs and preserving plain ASCII status text; run the runner with `powershell.exe -NoProfile`.
- Layer lock: test runner presentation only.
- Verify: full formal suite parses and all five suites run.

### F-014

- File: `herdr-skill/scripts/Initialize-HerdrProject.ps1`
- Change: resolve supported npm-based tools to their explicit Windows `.cmd` launcher, validate that path, and store it in the dispatch profile.
- Layer lock: executable discovery only.
- Verify: generated profile uses `opencode.cmd`/`codex.cmd`; explicit `Start-Process` version validation succeeds.

## Batch B — installation and synchronization correctness

### F-002, F-003, F-004

- File: `herdr-skill/scripts/Initialize-HerdrProject.ps1`
- Change: derive destinations only from selected target agents; preserve `.agents` as the universal project target; distinguish `agents_only` from all platforms; collect and throw copy failures; add source/copy version validation.
- Layer lock: installation deployment only; no workflow runtime changes.
- Verify: isolated fixture runs prove `agents_only` does not create platform-specific/global destinations, selected `codex` writes only expected locations, and a forced failed destination yields a visible nonzero failure.

### F-015, F-016

- File: `herdr-skill/scripts/Register-GlobalSkills.ps1`
- Change: derive package root from `$PSScriptRoot`, derive profile roots from `$env:USERPROFILE`, fail with an aggregated error on copy problems, and validate required `SKILL.md` plus file hashes after copy.
- Layer lock: explicit global-registration script only.
- Verify: static path check finds no hard-coded user/drive paths; fixture validation catches a missing or altered file.

## Batch C — durable workflow creation and agent lifecycle

### F-005, F-006

- Files: `herdr-skill/scripts/Start-HerdrWorkflow.ps1`, `herdr-skill/scripts/Start-HerdrParallelWorkflow.ps1`
- Change: persist a recoverable `initializing` workflow state before creating worktrees or launching agents; transition state only after successful launch; on failure write a blocked state and clean up resources created by this invocation.
- Layer lock: workflow creation and state persistence only.
- Verify: injected launcher/worktree failure leaves a discoverable blocked workflow and no untracked agent/worktree.

### F-007

- File: `herdr-skill/scripts/Start-HerdrAgent.ps1`
- Change: make post-launch setup transactional; if status, prompt, or watcher setup fails after agent creation, stop/close the started agent and record the cleanup result.
- Layer lock: agent launcher cleanup only.
- Verify: injected post-launch failure closes the pane/agent and leaves failure evidence.

### F-011, F-012, F-013

- Files: `herdr-skill/scripts/Resume-HerdrWorkflows.ps1`, `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1`, `herdr-skill/scripts/Watch-HerdrHandoff.ps1`
- Change: restore missing matrix agents from persisted matrix entries; make liveness require an active semantic agent status; tolerate transient invalid CLI JSON with bounded retries and durable blocked/error reporting.
- Layer lock: recovery, liveness and watcher behavior only.
- Verify: formal restart fixture recovers a missing matrix agent; inactive status is not treated as live; malformed transient agent-get output does not kill watcher.

## Batch D — monitor fencing and publication correctness

### F-008, F-009, F-010

- File: `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1`
- Change: remove target-branch fallback from failed feature-branch push; preserve a recoverable `push_failed`/blocked state rather than `merged`; introduce owner-fenced atomic lease renewal and validate ownership before every state mutation.
- Layer lock: publication and monitor lease/state transitions only.
- Verify: simulated feature-push failure never invokes target-branch push; failed publication is resumable and not terminal; competing monitor cannot write after lease ownership changes.

## Batch E — profile safety

### F-017

- Files: `herdr-skill/herdr/dispatch-profile.json`, `herdr-skill/scripts/Start-HerdrWorkflow.ps1`
- Change: mark the checked-in profile explicitly as a template and/or create an actionable startup path for an empty skill list; never reject ordinary task modes with a misleading missing-skill error without showing initialization remediation.
- Layer lock: profile validation/error messaging only.
- Verify: template profile produces an explicit actionable initialization error; initialized profile starts normally.

## Completion gates

1. Windows PowerShell formal suite passes all five suites.
2. Windows OpenCode/Codex launcher smoke tests use `.cmd` and pass.
3. Fresh fixture proves agent-target isolation and sync validation.
4. Failure-injection checks demonstrate no orphan state/resources and no false `merged` state.
5. All updated canonical scripts parse in Windows PowerShell 5.1; Node syntax checks remain green.
