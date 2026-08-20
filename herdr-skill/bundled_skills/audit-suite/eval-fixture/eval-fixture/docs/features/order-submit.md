# 订单提交功能

## 3.1 创建订单
- 用户填写商品 ID 和数量，点击提交
- 成功后展示：
  - 订单号 `order_no`
  - 应付总额 `payable_amount`
  - 促销文案 `discount_label`（无促销时展示空字符串，**必填展示位**）
- 失败时展示后端返回的 `error_message`

## 3.2 约束
- 金额字段必须与 OpenAPI `OrderResponse` 一致
