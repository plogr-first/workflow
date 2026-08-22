# AUDIT REPORT — workflow — 2026-08-23

## Pipeline | Rules Applied

- Mode: audit (static/runtime core audit; browser QA not applicable: this is a PowerShell/Node workflow package with no dev server or browser route).
- Rules applied: `AGENTS.md`, `CLAUDE.md`, local `audit-suite`, local `research-agent` evidence standard.
- API contract verification: SKIP — no project API/OpenAPI service or verifier was found.
- Runtime evidence: formal runner attempted under Windows PowerShell 5.1 and failed before executing suites because the script is UTF-8 without BOM and contains Unicode glyphs; see F-001.

## Findings

### F-001 — P1 BUG — formal verification runner cannot parse in Windows PowerShell 5.1

- File: `herdr-skill/tests_formal_audit/Run-All-Formal-Tests.ps1:48,54`
- Evidence: direct invocation with `powershell.exe -NoProfile ... -File` fails with `AmpersandNotAllowed` at line 48 and an unexpected token at line 54. File has no UTF-8 BOM; raw bytes show `&` inside a string and UTF-8 checkmark bytes parsed incorrectly by Windows PowerShell 5.1.
- Impact: the advertised full formal test suite exits before running any suite, so its claimed zero-tolerance result is not currently verifiable on the supported Windows host.
- Confidence: 10

### F-002 — P1 DRIFT — canonical initializer differs from all deployed copies

- Files: `herdr-skill/scripts/Initialize-HerdrProject.ps1:508-520` versus project/global `.agents/.claude/.codex/.opencode` copies.
- Evidence: source and eight deployed copies have different SHA-256 hashes; deployed copies lack the source `.agents/skills.json` block and current propagation logic.
- Impact: agents can execute stale initialization behavior; fixes made to the canonical workflow are not reliably propagated.
- Confidence: 9

### F-003 — P1 BUG — target-agent selection is bypassed by unconditional destinations

- File: `herdr-skill/scripts/Initialize-HerdrProject.ps1:474-482`
- Evidence: project and user global destinations for all platforms are added before `$agentArgs` filtering at lines 484-495. Selecting `agents_only` or a single platform therefore still writes other agent directories.
- Impact: cross-agent contamination and unintended overwrites; platform isolation promised by the selection UI is false.
- Confidence: 9

### F-004 — P1 BUG — skill copy errors are swallowed and installation can report success

- File: `herdr-skill/scripts/Initialize-HerdrProject.ps1:497-503`
- Evidence: the entire destination copy is inside `try { ... } catch {}` with an empty catch; later initialization/profile writing continues.
- Impact: partial or missing skill deployment is reported as successful, making later agent failures non-diagnostic and non-reproducible.
- Confidence: 9

### F-005 — P1 BUG — parallel workflow can create orphan agents/worktrees before master state exists

- File: `herdr-skill/scripts/Start-HerdrParallelWorkflow.ps1:74-154,173-200`
- Evidence: worktrees/agents start before the first master `workflow.json` write; intermediate failures leave processes/worktrees/events without resumable master state.
- Impact: orphaned processes and invisible workflows that cannot be resumed or cleaned up reliably.
- Confidence: 9

### F-006 — P1 BUG — serial workflow has the same orphan window

- File: `herdr-skill/scripts/Start-HerdrWorkflow.ps1:58-88`
- Evidence: task agent and deferred verifier are started before master workflow state is persisted; no `try/finally` cleanup covers launcher or state-write failures.
- Impact: failed launch can leave active agents/panes with no monitor/resume record.
- Confidence: 9

### F-007 — P1 BUG — started agent is not cleaned up after post-launch failure

- File: `herdr-skill/scripts/Start-HerdrAgent.ps1:324-344`
- Evidence: catch cleanup only closes a pane when `-not $agent`; once `$agent` exists, later status/prompt/watcher failures write `failure.json` but do not stop the already-started agent.
- Impact: orphan agents continue consuming resources and may mutate workflow state after the caller considers launch failed.
- Confidence: 9

### F-008 — P1 BUG — failed push can be recorded as merged

- File: `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1:373-374`
- Evidence: `Push-MergedWorkflow` failure is caught, `push_status=failed` is written, but state is still saved as `merged` and monitoring terminates.
- Impact: users and resume logic can treat an unpublished workflow as complete; no retry occurs.
- Confidence: 9

### F-009 — P1 BUG — feature push failure fallback may push target branch

- File: `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1:145-148`
- Evidence: feature-branch push failure falls back to `git push $remote $targetBranch`, then PR creation still references the feature branch.
- Impact: an unverified local target branch can be published remotely; this is an unsafe and potentially destructive recovery path.
- Confidence: 9

### F-010 — P1 BUG — lease renewal is non-atomic and can expire during long operations

- File: `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1:207-223`
- Evidence: 30-second lease is renewed with `Set-Content`; long network/git/agent operations are not fenced by an atomic lease/owner check.
- Impact: a second monitor can acquire the lease while the first still writes state/events, producing concurrent state corruption.
- Confidence: 9

### F-011 — P1 GAP — matrix child-agent recovery is not implemented

- Files: `herdr-skill/scripts/Resume-HerdrWorkflows.ps1:31-63`; `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1:237-325`
- Evidence: resume ensures only `task`/`verification`; `matrix_tasks` children are neither live-checked nor restarted, and monitor waits for outcomes.
- Impact: after restart or child loss, parallel workflows stall until timeout instead of recovering.
- Confidence: 9

### F-012 — P2 GAP — Agent-Live checks exit code but not semantic status

- File: `herdr-skill/scripts/Monitor-HerdrWorkflow.ps1:185-193`
- Evidence: `herdr agent get` is treated as live based on process exit code; blocked/error/idle statuses can still return exit 0.
- Impact: missing-role recovery is suppressed and workflows wait up to the full timeout with no actionable transition.
- Confidence: 8

### F-013 — P2 BUG — handoff watcher exits on transient empty/invalid CLI JSON

- File: `herdr-skill/scripts/Watch-HerdrHandoff.ps1:23-25`
- Evidence: direct `ConvertFrom-Json` is used under `ErrorActionPreference=Stop` without retry/validation.
- Impact: a temporary empty/error response kills the watcher and suppresses completion notification.
- Confidence: 8

### F-014 — P1 DRIFT — profile executable discovery can select `.ps1` instead of Windows `.cmd`

- File: `herdr-skill/scripts/Initialize-HerdrProject.ps1:663-669,710-730`
- Evidence: executable profile is derived from `Get-Command ... .Path`; current `Get-Command opencode` resolves to `opencode.ps1` while the Windows launcher is `opencode.cmd`.
- Impact: any downstream `Start-Process`/CreateProcess using stored profile executable can reproduce `%1 is not a valid Win32 application`.
- Confidence: 9

### F-015 — P1 BUG — global registration script is hard-coded to one machine and user profile

- File: `herdr-skill/scripts/Register-GlobalSkills.ps1:1,7-13`
- Evidence: source package is hard-coded as `F:\个人资料\workflow\herdr-skill` and all destination paths are hard-coded as `C:\Users\Lenovo\...` rather than deriving from `$PSScriptRoot` and `$env:USERPROFILE`.
- Impact: the package cannot register itself correctly after relocation, on another account, or on another machine; it can write to an unintended profile if those paths happen to exist.
- Confidence: 9

### F-016 — P2 GAP — registration verification only counts folder names

- File: `herdr-skill/scripts/Register-GlobalSkills.ps1:68-72`
- Evidence: verification enumerates each destination root and reports the count of matching top-level skill folders; it never validates required files or hashes.
- Impact: stale or partial copies can be reported as successfully registered, including the initializer drift observed in F-002.
- Confidence: 8

### F-017 — P1 BUG (conditional) — empty required-skill profile rejects all normal workflow modes

- Files: `herdr-skill/herdr/dispatch-profile.json:19`; `herdr-skill/scripts/Start-HerdrWorkflow.ps1:34-36`
- Evidence: the checked-in profile has `mattpocock_skills: {}`, while startup rejects task/bugfix/research when required skills are absent.
- Impact: if this checked-in profile is used as an active profile, all normal workflow modes fail before dispatch. This is conditional because it may be intended only as a template.
- Confidence: 8

## Runtime checks

- Direct `opencode --version`: PASS (`1.18.21`).
- Explicit `Start-Process` of `opencode.cmd`: PASS.
- All 19 discovered repair-script copies: PASS hash consistency after the previous launcher fix.
- Formal suite: BLOCKED by F-001 before suite execution.
- Node syntax check: PASS for 6 JS files.

## Status

DONE_WITH_CONCERNS — audit complete; fixes are not applied in this audit phase.

## Next

Select repair scope: `F-001,F-002,F-003,F-004,F-005,F-006,F-007,F-008,F-009,F-010,F-011,F-012,F-013,F-014` or a subset. Fixes should be staged in dependency order and re-run the formal suite after F-001.
