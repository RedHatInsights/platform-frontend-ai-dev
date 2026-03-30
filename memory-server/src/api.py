"""REST API endpoints for the web dashboard."""
import json

from starlette.requests import Request
from starlette.responses import JSONResponse

from .db import get_pool
from .embeddings import embed
from .events import Event, bus


async def api_tasks(request: Request) -> JSONResponse:
    pool = get_pool()
    status = request.query_params.get("status")
    limit = int(request.query_params.get("limit", "20"))
    offset = int(request.query_params.get("offset", "0"))

    if status:
        total = await pool.fetchval(
            "SELECT COUNT(*) FROM tasks WHERE status = $1::task_status", status
        )
        rows = await pool.fetch(
            "SELECT * FROM tasks WHERE status = $1::task_status ORDER BY created_at DESC LIMIT $2 OFFSET $3",
            status, limit, offset,
        )
    else:
        total = await pool.fetchval("SELECT COUNT(*) FROM tasks")
        rows = await pool.fetch(
            "SELECT * FROM tasks ORDER BY created_at DESC LIMIT $1 OFFSET $2",
            limit, offset,
        )
    return JSONResponse({
        "items": [_task(r) for r in rows],
        "total": total,
        "limit": limit,
        "offset": offset,
    })


async def api_memories(request: Request) -> JSONResponse:
    pool = get_pool()
    category = request.query_params.get("category")
    repo = request.query_params.get("repo")
    tag = request.query_params.get("tag")
    limit = int(request.query_params.get("limit", "20"))
    offset = int(request.query_params.get("offset", "0"))

    conditions, params, idx = [], [], 0
    if category:
        idx += 1; conditions.append(f"category = ${idx}"); params.append(category)
    if repo:
        idx += 1; conditions.append(f"repo = ${idx}"); params.append(repo)
    if tag:
        idx += 1; conditions.append(f"${idx} = ANY(tags)"); params.append(tag)

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    total = await pool.fetchval(
        f"SELECT COUNT(*) FROM memories {where}", *params
    )

    idx += 1; params.append(limit)
    limit_idx = idx
    idx += 1; params.append(offset)
    offset_idx = idx

    rows = await pool.fetch(
        f"SELECT id, category, repo, jira_key, title, content, tags, created_at, metadata FROM memories {where} ORDER BY created_at DESC LIMIT ${limit_idx} OFFSET ${offset_idx}",
        *params,
    )
    return JSONResponse({
        "items": [_memory(r) for r in rows],
        "total": total,
        "limit": limit,
        "offset": offset,
    })


async def api_memory_search(request: Request) -> JSONResponse:
    pool = get_pool()
    query = request.query_params.get("q", "")
    if not query:
        return JSONResponse({"error": "missing ?q= parameter"}, status_code=400)

    category = request.query_params.get("category")
    repo = request.query_params.get("repo")
    tag = request.query_params.get("tag")
    limit = int(request.query_params.get("limit", "10"))

    vector = embed(query)
    conditions, params, idx = [], [vector, limit], 2
    if category:
        idx += 1; conditions.append(f"category = ${idx}"); params.append(category)
    if repo:
        idx += 1; conditions.append(f"repo = ${idx}"); params.append(repo)
    if tag:
        idx += 1; conditions.append(f"${idx} = ANY(tags)"); params.append(tag)

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    rows = await pool.fetch(
        f"""
        SELECT id, category, repo, jira_key, title, content, tags, created_at, metadata,
               embedding <=> $1 AS distance
        FROM memories {where}
        ORDER BY distance LIMIT $2
        """,
        *params,
    )
    return JSONResponse([{**_memory(r), "similarity": round(1 - r["distance"], 4)} for r in rows])


async def api_memory_embeddings(request: Request) -> JSONResponse:
    """Return 3D projected embeddings for visualization (PCA)."""
    pool = get_pool()
    rows = await pool.fetch(
        "SELECT id, title, content, category, repo, tags, embedding FROM memories ORDER BY created_at DESC LIMIT 200"
    )
    if not rows:
        return JSONResponse([])

    import numpy as np
    embeddings = np.array([list(r["embedding"]) for r in rows])

    # Center and PCA → 3 components
    mean = embeddings.mean(axis=0)
    centered = embeddings - mean
    n_components = min(3, len(rows), centered.shape[1])
    if len(rows) > 2:
        U, S, Vt = np.linalg.svd(centered, full_matrices=False)
        proj = centered @ Vt[:n_components].T
    else:
        proj = centered[:, :n_components]

    # Pad to 3D if needed
    if proj.shape[1] < 3:
        proj = np.pad(proj, ((0, 0), (0, 3 - proj.shape[1])))

    # Normalize to [-1, 1] range for Three.js
    max_abs = np.abs(proj).max(axis=0)
    max_abs[max_abs == 0] = 1
    proj = proj / max_abs

    result = []
    for i, r in enumerate(rows):
        result.append({
            "id": r["id"],
            "title": r["title"],
            "content": r["content"][:200],
            "category": r["category"],
            "repo": r["repo"],
            "tags": list(r["tags"]) if r["tags"] else [],
            "x": float(proj[i, 0]),
            "y": float(proj[i, 1]),
            "z": float(proj[i, 2]),
        })
    return JSONResponse(result)


async def api_memory_get(request: Request) -> JSONResponse:
    """Get a single memory by ID."""
    pool = get_pool()
    memory_id = request.path_params.get("id")
    if not memory_id:
        return JSONResponse({"error": "missing memory id"}, status_code=400)
    row = await pool.fetchrow(
        "SELECT id, category, repo, jira_key, title, content, tags, created_at, metadata FROM memories WHERE id = $1",
        int(memory_id),
    )
    if not row:
        return JSONResponse({"error": f"Memory {memory_id} not found"}, status_code=404)
    return JSONResponse(_memory(row))


async def api_memory_delete(request: Request) -> JSONResponse:
    """Delete a memory by ID."""
    pool = get_pool()
    memory_id = request.path_params.get("id")
    if not memory_id:
        return JSONResponse({"error": "missing memory id"}, status_code=400)
    result = await pool.execute("DELETE FROM memories WHERE id = $1", int(memory_id))
    if result == "DELETE 0":
        return JSONResponse({"error": f"Memory {memory_id} not found"}, status_code=404)
    await bus.publish(Event("memory_deleted", {"id": int(memory_id)}))
    return JSONResponse({"deleted": True, "id": int(memory_id)})


async def api_tags(request: Request) -> JSONResponse:
    pool = get_pool()
    rows = await pool.fetch(
        "SELECT DISTINCT unnest(tags) AS tag FROM memories ORDER BY tag"
    )
    return JSONResponse([r["tag"] for r in rows])


async def api_stats(request: Request) -> JSONResponse:
    pool = get_pool()
    tasks_by_status = await pool.fetch(
        "SELECT status::text, COUNT(*) as count FROM tasks GROUP BY status"
    )
    memory_count = await pool.fetchval("SELECT COUNT(*) FROM memories")
    memories_by_cat = await pool.fetch(
        "SELECT category, COUNT(*) as count FROM memories GROUP BY category"
    )
    memories_by_repo = await pool.fetch(
        "SELECT COALESCE(repo, 'unset') as repo, COUNT(*) as count FROM memories GROUP BY repo ORDER BY count DESC"
    )
    return JSONResponse({
        "tasks": {r["status"]: r["count"] for r in tasks_by_status},
        "memories": {
            "total": memory_count,
            "by_category": {r["category"]: r["count"] for r in memories_by_cat},
            "by_repo": {r["repo"]: r["count"] for r in memories_by_repo},
        },
    })


def _task(row) -> dict:
    return {
        "id": row["id"],
        "jira_key": row["jira_key"],
        "status": row["status"],
        "repo": row["repo"],
        "branch": row["branch"],
        "pr_number": row["pr_number"],
        "pr_url": row["pr_url"],
        "title": row.get("title"),
        "summary": row.get("summary"),
        "created_at": row["created_at"].isoformat(),
        "last_addressed": row["last_addressed"].isoformat(),
        "paused_reason": row["paused_reason"],
        "metadata": json.loads(row["metadata"]) if isinstance(row["metadata"], str) else (row["metadata"] or {}),
    }


def _memory(row) -> dict:
    return {
        "id": row["id"],
        "category": row["category"],
        "repo": row["repo"],
        "jira_key": row["jira_key"],
        "title": row["title"],
        "content": row["content"],
        "tags": list(row["tags"]) if row["tags"] else [],
        "created_at": row["created_at"].isoformat(),
        "metadata": json.loads(row["metadata"]) if isinstance(row["metadata"], str) else (row["metadata"] or {}),
    }
