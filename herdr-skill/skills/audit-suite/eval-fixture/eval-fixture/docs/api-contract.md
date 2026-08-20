# API Contract (legacy draft — may be stale)

## POST /api/orders

**Response 200 — OrderResponse**

| Field | Type | Required |
|-------|------|----------|
| order_no | string | yes |
| payable_amount | number | yes |
| discount_label | string | yes |

> PM 2024-03: 必须返回 discount_label，前端已按此联调。

**Note:** 若与 `openapi.yaml` 不一致，以实现代码为准。（此注记常被忽略）
