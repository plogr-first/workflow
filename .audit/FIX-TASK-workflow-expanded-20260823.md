# FIX TASK — workflow expanded findings — 2026-08-23

用户已明确要求：全部修复（F-001、F-002、F-003）。

## F-001 — Remove user-specific audit skill path

- Files: `herdr-skill/bundled_skills/plogr/SKILL.md`, `herdr-skill/scripts/Start-HerdrAgent.ps1`
- Change: replace the Lenovo-specific absolute path with the project skill registry/discovery rule; preserve read-only audit sequencing.
- Layer lock: documentation and prompt construction only; no change to agent role semantics.
- Verify: expanded contract test rejects `C:\Users\` in distributed payload and launcher prompt; project initialization and formal suite remain green.

## F-002 — Add registry verification to CI

- File: `herdr-skill/.github/workflows/windows-formal-tests.yml`
- Change: add an initialized temporary project fixture and invoke `Test-HerdrSkillRegistry.ps1` in CI before formal tests.
- Layer lock: CI workflow only; no production runtime behavior change.
- Verify: CI YAML remains valid; local registry test passes; `npm test` passes.

## F-003 — Full-tree global registration validation

- File: `herdr-skill/scripts/Register-GlobalSkills.ps1`
- Change: validate every copied file against a recursive SHA256 manifest, while retaining legacy payload exclusions and existing destination behavior.
- Layer lock: registration verification only; no deletion outside managed skill destinations.
- Verify: global registration passes and reports full-file counts; representative global copies match source manifests; formal suite passes.

## Acceptance

- No user-specific absolute path in distributed skill/runtime prompt payload.
- Project and global skill copies are full-tree hash-consistent.
- CI executes registry verification.
- `npm run test:contract`, `npm run pack:check`, `npm test` all pass.
