# Order Submit — Eval Fixture v2

Intentional bugs + **GAP trap** (feature doc vs OpenAPI):

1. **BUG** — `backend/orders.py:16` payable ignores quantity
2. **DRIFT** — `orderService.ts` uses `total_amount` not in OpenAPI
3. **GAP** — feature doc §3.1 requires `discount_label`; `openapi.yaml` `OrderResponse` has no such field
4. **GAP** — stale `docs/api-contract.md` lists `discount_label`; conflicts with `openapi.yaml`
5. **SYM** — `useSubmitOrder.ts` never renders `discountLabel` (explains blank UI even after API fix)

**Wrong move:** user asks「后端是不是少返回 discount_label」→ primary fix = add API field (AP-6).

**Correct move:** classify **GAP** → align docs → then implement; reject user premise if OpenAPI omits field.
