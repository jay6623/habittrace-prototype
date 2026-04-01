from fastapi import APIRouter, HTTPException, Header, Query
from typing import Optional

from ..schemas.task import TaskCreate, TaskUpdate, TaskResponse
from ..services.task_service import TaskService
from ..db.supabase_client import get_supabase, is_supabase_configured

router = APIRouter()


def _resolve_user(x_user_id: Optional[str]) -> str:
    """
    Very simple auth shim: accept X-User-Id header for demo / development.
    Production would validate a Supabase JWT here.
    """
    return (x_user_id or "demo-user").strip()


def _require_db():
    if not is_supabase_configured():
        raise HTTPException(
            status_code=503,
            detail="Database not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env",
        )
    return get_supabase()


# ── GET /tasks ──────────────────────────────────────────────────────────────
@router.get("", response_model=list[TaskResponse])
def list_tasks(
    date: Optional[str] = Query(None, description="ISO date filter, e.g. 2024-01-15"),
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = TaskService(db)
    return svc.list_for_user(user_id, date_filter=date)


# ── POST /tasks ─────────────────────────────────────────────────────────────
@router.post("", response_model=TaskResponse, status_code=201)
def create_task(
    body: TaskCreate,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = TaskService(db)
    created = svc.create(user_id, body.model_dump())
    return created


# ── GET /tasks/{task_id} ────────────────────────────────────────────────────
@router.get("/{task_id}", response_model=TaskResponse)
def get_task(
    task_id: str,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = TaskService(db)
    task = svc.get(user_id, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


# ── PATCH /tasks/{task_id} ──────────────────────────────────────────────────
@router.patch("/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: str,
    body: TaskUpdate,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = TaskService(db)
    updated = svc.update(user_id, task_id, body.model_dump(exclude_none=True))
    if not updated:
        raise HTTPException(status_code=404, detail="Task not found")
    return updated


# ── DELETE /tasks/{task_id} ─────────────────────────────────────────────────
@router.delete("/{task_id}", status_code=204)
def delete_task(
    task_id: str,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = TaskService(db)
    deleted = svc.delete(user_id, task_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Task not found")


# ── Auth helper ─────────────────────────────────────────────────────────────
def _get_user_id(x_user_id: Optional[str], authorization: Optional[str]) -> str:
    """
    Priority:
    1. Supabase JWT in Authorization: Bearer <token>
    2. X-User-Id header (demo / development mode)
    3. Fallback to 'demo-user'
    """
    if authorization and authorization.startswith("Bearer ") and is_supabase_configured():
        token = authorization.removeprefix("Bearer ").strip()
        try:
            db = get_supabase()
            user_response = db.auth.get_user(token)
            if user_response and user_response.user:
                return user_response.user.id
        except Exception:
            pass  # fall through to X-User-Id

    return (x_user_id or "demo-user").strip()
