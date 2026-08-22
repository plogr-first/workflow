# Audit Suite — Hard Constraints

These rules apply to all modes. Change rarely via `learn --promote` only after user confirms.

## Iron Laws

1. **Read-only audit** — Audit modes never edit project source code.
2. **Confirm before fix** — Fix modes require FIX-TASK approval before edits.
3. **Project rules first** — `CLAUDE.md`, `AGENTS.md`, `agents.md`, `.cursor/rules/`, `rules.md` override skill knowledge in the current repo.
4. **Evidence required** — Static findings need `file:line` + code quote. QA findings need repro + console or screenshot.

## Finding Categories (only these four)

| Category | Meaning |
|----------|---------|
| **BUG** | Verified incorrect behavior or logic error |
| **DRIFT** | Code deviates from declared contract |
| **GAP** | Declared documents disagree |
| **MISSING** | Feature doc requires something code and API doc do not satisfy |

**Forbidden:** SUGGESTION, REFACTOR, NICE-TO-HAVE, ENHANCEMENT

## Contract Direction

1. Feature doc > API doc > code comments (scope)
2. API doc matches backend but feature doc requires more → GAP or MISSING, not "add API field" by default
3. Frontend uses undeclared property → DRIFT (client error)
4. MISSING only when **both** feature doc and API doc declare requirement and backend lacks it

## Pre-emit Gate

- Quote motivating lines at `file:line` (or runtime Q-xxx)
- Confidence ≥ 7 for static findings or appendix only
- Scope anchor required
- Check rejections.jsonl and pitfalls anti-patterns

## Fix Constraints

- Minimal diff; respect project layering
- No drive-by refactors
- Ad-hoc fix: default ≤ 3 files unless user approves

## Knowledge Layers

- **constraints.md** — universal structural rules (this file)
- **pitfalls.jsonl** — cross-project lessons (`learn` mode)
- **Project rule files** — repo-specific; never copy project names into pitfalls
