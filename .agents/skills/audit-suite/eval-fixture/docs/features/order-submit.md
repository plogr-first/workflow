# 订单提交功能

## 3.1 创建订单
- 用户填写商品 ID 和数量，点击提交
- 成功后展示订单号 `order_no` 和应付总额 `payable_amount`
- 失败时展示后端返回的 `error_message`

## 3.2 约束
- 金额字段必须与 OpenAPI `OrderResponse` 一致
