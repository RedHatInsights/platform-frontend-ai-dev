import os
from pathlib import Path

import asyncpg
from pgvector.asyncpg import register_vector

_pool: asyncpg.Pool | None = None


async def init_pool() -> asyncpg.Pool:
    global _pool
    url = os.environ.get("DATABASE_URL", "postgresql://bot:bot@localhost:5433/bot_memory")

    # First, run schema (creates the vector extension) using a direct connection
    conn = await asyncpg.connect(url)
    schema = (Path(__file__).parent / "schema.sql").read_text()
    await conn.execute(schema)
    await conn.close()

    # Now create the pool — _init_conn can register the vector type safely
    _pool = await asyncpg.create_pool(url, min_size=2, max_size=10, init=_init_conn)
    return _pool


async def _init_conn(conn: asyncpg.Connection):
    await register_vector(conn)


def get_pool() -> asyncpg.Pool:
    if _pool is None:
        raise RuntimeError("Database pool not initialized")
    return _pool


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
