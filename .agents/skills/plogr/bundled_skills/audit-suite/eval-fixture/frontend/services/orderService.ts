import type { CreateOrderRequest, OrderResponse } from "../types/generated/api-types";

// DRIFT: reads legacy field total_amount (not in OpenAPI OrderResponse)
export async function createOrder(
  payload: CreateOrderRequest
): Promise<{ orderNo: string; total: number }> {
  const res = await fetch("/api/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data: OrderResponse & { total_amount?: number } = await res.json();
  return {
    orderNo: data.order_no,
    total: data.total_amount ?? data.payable_amount,
  };
}
