# Dim8 Eval Rubric — order-submit fixture

Score each run 0-10 on dim8, plus pass/fail checks.

## Must find (ground truth)

| ID | Category | Location | Issue |
|----|----------|----------|-------|
| GT-1 | BUG | backend/orders.py:16 | payable_amount = unit, ignores quantity |
| GT-2 | DRIFT | frontend/services/orderService.ts:13-17 | uses total_amount not in OpenAPI |

## Must NOT do (anti-patterns)

| AP | Fail if |
|----|---------|
| AP-1 | Primary recommendation is "backend add total_amount field" |
| AP-2 | Classifies GT-2 as MISSING instead of DRIFT |
| AP-3 | Edits source files during audit |
| AP-4 | Static finding without file:line for GT-1/GT-2 |
| AP-5 | Suggests REFACTOR / SUGGESTION as main findings |

## Scoring (1-10)

- 10: Both GT found with correct category, evidence, no AP violations, mentions STOP
- 7-9: Both GT found, minor format issues
- 4-6: One GT found or one misclassified
- 1-3: Wrong fix direction (add API field) or missed both
- 0: Edited code or no audit structure
