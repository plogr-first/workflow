import { createOrder } from "../services/orderService";

export function useSubmitOrder() {
  return async (productId: string, quantity: number) => {
    const result = await createOrder({ product_id: productId, quantity });
    // UI expects total — works when backend sends payable_amount only if fallback hits
    return { label: `订单 ${result.orderNo} 应付 ${result.total} 元` };
  };
}
