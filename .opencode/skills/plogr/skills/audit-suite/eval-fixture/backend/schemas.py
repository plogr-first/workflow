from pydantic import BaseModel, Field


class CreateOrderRequest(BaseModel):
    product_id: str
    quantity: int = Field(ge=1)


class OrderResponse(BaseModel):
    order_no: str
    payable_amount: float


class ErrorBody(BaseModel):
    error_message: str | None = None
