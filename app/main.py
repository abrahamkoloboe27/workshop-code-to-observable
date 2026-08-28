"""FastAPI application factory."""

import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from app.config import get_settings
from app.db import create_pool
from app.metrics import REQUEST_DURATION
from app.routers import health, items, orders


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    pool = create_pool(settings)
    # Does not wait for the database: the app must boot even when Postgres is
    # still starting. /ready is what tells the truth about that.
    await pool.open()
    app.state.pool = pool
    try:
        yield
    finally:
        await pool.close()


def create_app() -> FastAPI:
    app = FastAPI(title="Workshop — From Code to Observable", lifespan=lifespan)

    @app.middleware("http")
    async def record_duration(request: Request, call_next):
        started = time.perf_counter()
        response = await call_next(request)
        REQUEST_DURATION.labels(
            method=request.method,
            path=request.scope.get("route").path
            if request.scope.get("route")
            else request.url.path,
            status=str(response.status_code),
        ).observe(time.perf_counter() - started)
        return response

    @app.get("/metrics", include_in_schema=False)
    async def metrics() -> Response:
        return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

    app.include_router(health.router)
    app.include_router(items.router)
    app.include_router(orders.router)
    return app


app = create_app()