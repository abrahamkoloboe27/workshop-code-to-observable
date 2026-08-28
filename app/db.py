"""Database access: one async connection pool, opened at startup."""

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from app.config import Settings


def create_pool(settings: Settings) -> AsyncConnectionPool:
    return AsyncConnectionPool(
        conninfo=settings.database_url,
        min_size=settings.pool_min_size,
        max_size=settings.pool_max_size,
        timeout=settings.pool_timeout,
        kwargs={"row_factory": dict_row},
        open=False,
    )


async def ping(pool: AsyncConnectionPool) -> None:
    """Raise if the database does not answer. Used by GET /ready."""
    async with pool.connection() as conn:
        await conn.execute("SELECT 1")


async def fetch_all(pool: AsyncConnectionPool, query: str) -> list[dict]:
    async with pool.connection() as conn:
        cursor = await conn.execute(query)
        return await cursor.fetchall()
