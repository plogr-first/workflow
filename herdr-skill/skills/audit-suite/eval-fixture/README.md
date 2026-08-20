# Order Submit — Eval Fixture

Intentional bugs for audit-suite dim8 test (do not fix during audit run):

1. **Backend BUG** — `backend/orders.py:16` ignores `quantity` in payable_amount
2. **Frontend DRIFT** — `frontend/services/orderService.ts:13-17` uses `total_amount` not in OpenAPI
3. **Feature vs API GAP trap** — feature doc says show `payable_amount`; wrong fix is "add total_amount to API"

Run audit in **read-only** mode against this folder.
