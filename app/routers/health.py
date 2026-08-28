"""Liveness and readiness probes.

/health answers without touching anything external: it says "the process is up".
/ready runs a SELECT 1: it says "the process can actually serve traffic".
"""

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.db import ping

router = APIRouter(tags=["probes"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/ready")
async def ready(request: Request) -> JSONResponse:
    try:
        await ping(request.app.state.pool)
    except Exception as exc:  # noqa: BLE001 - any failure means "not ready"
        return JSONResponse(
            status_code=503,
            content={"status": "unavailable", "detail": str(exc)},
        )
    return JSONResponse(status_code=200, content={"status": "ready"})
