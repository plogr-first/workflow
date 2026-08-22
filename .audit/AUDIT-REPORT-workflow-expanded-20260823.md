# AUDIT REPORT — workflow expanded review — 2026-08-23

## Pipeline

- Mode: audit (static-only; no browser/server flow exists for this package)
- Rules Applied: `F:\个人资料\workflow\AGENTS.md`, `F:\个人资料\workflow\CLAUDE.md`
- Scope: `F:\个人资料\workflow\herdr-skill`, project registrations, CI contract, and real `plogr show/status` entrypoints
- Latest evidence: registry verification (6 platforms / 1206 files), contract PASS, pack check PASS, formal suite PASS

## Findings

### F-001 — P1 DRIFT — user-specific audit skill path remains in distributed payload

- File: `F:\个人资料\workflow\herdr-skill\bundled_skills\plogr\SKILL.md:37`
- Also: `F:\个人资料\workflow\herdr-skill\scripts\Start-HerdrAgent.ps1:218,231`
- Evidence: instructions hard-code `C:\Users\Lenovo\.agents\skills\audit-suite`.
- Impact: a project copied to another Windows account or CI runner will reference a nonexistent path; the documented project registry contract is bypassed for bugfix triage.
- Confidence: 10

### F-002 — P2 GAP — CI does not verify the project full-file registry manifest

- File: `F:\个人资料\workflow\herdr-skill\.github\workflows\windows-formal-tests.yml:13-22`
- Evidence: CI runs `pack:check`, `test:contract`, and `npm test`, but never invokes `scripts/Test-HerdrSkillRegistry.ps1` against an initialized project registry.
- Impact: a stale or incomplete `.agents/project-skills.json` can pass CI; the long-term full-tree hash guarantee is currently local-only.
- Confidence: 9

### F-003 — P2 GAP — global registration validates only `SKILL.md`, not the full skill tree

- File: `F:\个人资料\workflow\herdr-skill\scripts\Register-GlobalSkills.ps1:27-35,55`
- Evidence: `Assert-SkillCopy` hashes only source/destination `SKILL.md`, and reports “verified with SKILL.md hashes”.
- Impact: reference files, scripts, or agents metadata can drift silently in global installations while the registration command reports success.
- Confidence: 9

## Passed checks

- BOM-compatible `plogr show/status` entrypoint: PASS after latest CLI fix.
- Project registry: PASS (6 platforms / 1206 files).
- Runtime contract: PASS.
- Package dry-run: PASS.
- `skill-creator` validation for canonical and alias skills: PASS.
- Formal Flow A/B/C/D and boundary suite: PASS.

## Next

Stop at audit checkpoint. Fix candidates: `F-001`, `F-002`, `F-003`.
