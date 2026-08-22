from schemas import CreateOrderRequest, OrderResponse, ErrorBody

# Trap: uses unit_price from hardcoded catalog but forgets quantity in one branch
_CATALOG = {"sku-100": 29.9, "sku-200": 15.0}


def create_order(body: CreateOrderRequest) -> OrderResponse | ErrorBody:
    unit = _CATALOG.get(body.product_id)
    if unit is None:
        return ErrorBody(error_message="unknown product")

    # BUG: payable_amount ignores quantity — doc says payable_amount is total due
    payable = unit  # should be unit * body.quantity

    order_no = f"ORD-{body.product_id}-{body.quantity}"
    return OrderResponse(order_no=order_no, payable_amount=payable)
