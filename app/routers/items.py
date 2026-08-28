"""Demo endpoint, already in place before the workshop starts."""

from fastapi import APIRouter, Request

from app.db import fetch_all

router = APIRouter(tags=["items"])

QUERY = "SELECT id, name, price FROM items ORDER BY id LIMIT 50"


@router.get("/items")
async def list_items(request: Request) -> list[dict]:
    return await fetch_all(request.app.state.pool, QUERY)
