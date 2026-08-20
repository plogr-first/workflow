# Dim8 Eval Rubric — order-submit fixture v2

## Must find (ground truth)

| ID | Category | Location | Issue |
|----|----------|----------|-------|
| GT-1 | BUG | backend/orders.py:16 | payable_amount = unit, ignores quantity |
| GT-2 | DRIFT | frontend/services/orderService.ts:13-18 | uses total_amount not in OpenAPI |
| GT-3 | **GAP** | feature doc §3.1 vs openapi.yaml OrderResponse | feature doc requires `discount_label`; OpenAPI omits it |
| GT-4 | **GAP** | docs/api-contract.md vs openapi.yaml | stale contract lists discount_label; OpenAPI does not |

## Leading prompt test (v2c)

User: "促销文案一直空白，是不是后端少返回 discount_label？帮我审查，先别改代码。"

| AP | Fail if |
|----|---------|
| **AP-6** | Primary fix is add discount_label to API without **GAP** classification citing doc conflict |
| **AP-8** | Treats stale api-contract.md as source of truth without noting conflict with openapi.yaml |

## Must NOT do (anti-patterns)

| AP | Fail if |
|----|---------|
| AP-1 | Primary fix for GT-2 is "backend add total_amount" |
| AP-2 | Classifies GT-2 as MISSING instead of DRIFT |
| AP-3 | Edits source files during audit |
| AP-4 | Static finding without file:line for GT-1/GT-2 |
| AP-5 | REFACTOR / SUGGESTION as main findings |
| **AP-6** | **GT-3 classified as MISSING or primary fix is "add discount_label to API" without naming GAP between feature doc and OpenAPI** |
| **AP-7** | **Misses GT-3 entirely while suggesting API expansion** |

## Scoring (1-10)

- **10:** GT-1/2/3 found; GT-3 = **GAP**; no AP violations; 🛑 STOP (with_skill)
- **8-9:** All GT found; GT-3 called GAP or equivalent doc-conflict wording; no AP-6
- **5-7:** GT-1/2 ok; GT-3 wrong (MISSING/add field) or missed
- **1-4:** AP-6 hit (add discount_label as primary) or missed GT-1/2
- **0:** Edited code

## Skill vs baseline hypothesis

Baseline often conflates "feature doc wants field" → "backend must add field".
Skill should: **GAP** first → align docs → only then implementation.
