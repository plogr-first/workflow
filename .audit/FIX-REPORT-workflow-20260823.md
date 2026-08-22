# FIX REPORT — workflow — 2026-08-23

## Result

All findings approved in `FIX-TASK-workflow-20260823.md` were repaired and verified.

## Repairs

- Windows launchers now select explicit npm `.cmd` executables; no Anaconda path was removed.
- Project/global skill deployment derives paths from its package location, verifies copied hashes, honors selected agent targets, and now always uses the canonical package root for `plogr` and `herdr` rather than a possible stale bundled copy.
- Workflow dispatch and parallel dispatch persist recoverable initialization state, record launch failures as blocked, and clean up resources created by a failed invocation.
- Agent startup cleanup, matrix-agent recovery, semantic liveness, transient CLI JSON handling, owner-fenced atomic leases, and resumable failed publication are implemented.
- Publication never falls back to pushing the target branch after a feature-branch push failure. `create_pr` pushes the feature branch and then creates the PR.
- Windows PowerShell Git handling now treats expected cleanup absence and successful stderr progress correctly while still failing actual worktree, merge, and push errors.
- Monitor hashing and global-registration hashing use .NET SHA-256, removing dependency on module auto-loading in constrained PowerShell child hosts.
- The checked-in dispatch profile is marked as a template, and initialization produces an actionable profile.

## Verification

- Windows PowerShell 5.1 formal suite: `PASS` (240.05 seconds).
  - Flow A: task -> independent verification -> merge/prune
  - Flow B: bugfix repair loop -> knowledge harvest
  - Flow C: parallel matrix -> integration -> conflict block -> prune
  - Flow D: restart recovery -> lease/session guard -> bounded generations
  - Boundaries: Chinese/special paths, depth-20 atomic JSON, five-way lease race, GitHub PR flow, HERDR_ENV guard
- `python --version`: `Python 3.13.11`; `D:\anaconda\python.exe` remains on PATH but is not the default.
- `opencode.cmd --version`: `1.18.21`; `codex.cmd --version`: `codex-cli 0.149.0`.
- Canonical source hashes match project `.agents`, `.claude`, `.codex`, `.opencode` copies and user-level `.agents`, `.codex`, `.opencode` copies for the repaired workflow scripts.

## Notes

Git may still print LF/CRLF warnings during fixture commits. These are non-failing Git configuration warnings, not workflow errors.
