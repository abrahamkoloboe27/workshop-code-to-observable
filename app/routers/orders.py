"""Orders endpoint — this is the change the workshop follows across five floors."""

from fastapi import APIRouter, Request

from app.db import fetch_all
from app.metrics import ORDERS_REQUESTS

router = APIRouter(tags=["orders"])

QUERY = "SELECT id, customer, amount, status FROM orders ORDER BY id LIMIT 50"


@router.get("/orders")
async def list_orders(request: Request) -> list[dict]:
    ORDERS_REQUESTS.inc()
    return await fetch_all(request.app.state.pool, QUERY)
