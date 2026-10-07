from fastapi import APIRouter, HTTPException, Query

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..schemas.task import TaskCreate, TaskPlanningFields, TaskResponse, TaskUpdate
from ..services.google_calendar_service import GoogleCalendarService
from ..services.task_ai_sync_service import sync_task_ai_safely
from ..services.task_service import TaskService

router = APIRouter()


def _require_db():
    if not is_supabase_configured():
        raise HTTPException(
            status_code=503,
            detail=(
                "Database not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env"
            ),
        )
    return get_supabase()


# ── GET /tasks ──────────────────────────────────────────────────────────────
@router.get("", response_model=list[TaskResponse])
def list_tasks(
    user_id: CurrentUserId,
    date: str | None = Query(None, description="ISO date filter, e.g. 2024-01-15"),
):
    db = _require_db()
    svc = TaskService(db)
    rows = svc.list_for_user(str(user_id), date_filter=date)
    # Retry only a small batch on reads; stop after an outage to avoid a slow
    # remote request for every task. The queue remains durable for later reads.
    retried = 0
    for index, task in enumerate(rows):
        if task.get("ai_sync_status") == "pending" and retried < 3:
            rows[index] = sync_task_ai_safely(db, task)
            retried += 1
            if rows[index].get("ai_sync_status") != "synced":
                break
    return rows


class TaskAISyncRequest(TaskPlanningFields):
    timezone_name: str = "UTC"


@router.post("/{task_id}/ai-plan", response_model=TaskResponse)
def ensure_task_ai_plan(task_id: str, body: TaskAISyncRequest, user_id: CurrentUserId):
    svc = TaskService(_require_db())
    task = svc.get(str(user_id), task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    if not task.get("ai_plan_input_id"):
        if task.get("task_status") != "pending":
            raise HTTPException(
                status_code=409, detail="Past outcomes cannot create a new AI input."
            )
        # Validation is shared with task writes. The DB trigger captures the
        # existing plan as a new snapshot, never a backdated training example.
        update = TaskUpdate(timezone_name=body.timezone_name)
        task = svc.update(str(user_id), task_id, {
            **update.model_dump(exclude_unset=True), "ai_sync_status": "pending",
        })
    if task is None or task.get("ai_sync_status") != "synced":
        raise HTTPException(status_code=503, detail="AI plan sync is pending. Please retry later.")
    return task


# ── POST /tasks ─────────────────────────────────────────────────────────────
@router.post("", response_model=TaskResponse, status_code=201)
def create_task(
    body: TaskCreate,
    user_id: CurrentUserId,
):
    db = _require_db()
    svc = TaskService(db)
    created = svc.create(str(user_id), body.model_dump())
    GoogleCalendarService(db).sync_task_safely(str(user_id), created)
    return created


# ── GET /tasks/{task_id} ────────────────────────────────────────────────────
@router.get("/{task_id}", response_model=TaskResponse)
def get_task(
    task_id: str,
    user_id: CurrentUserId,
):
    db = _require_db()
    svc = TaskService(db)
    task = svc.get(str(user_id), task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


# ── PATCH /tasks/{task_id} ──────────────────────────────────────────────────
@router.patch("/{task_id}", response_model=TaskResponse)
def update_task(
    task_id: str,
    body: TaskUpdate,
    user_id: CurrentUserId,
):
    db = _require_db()
    svc = TaskService(db)
    updated = svc.update(str(user_id), task_id, body.model_dump(exclude_unset=True))
    if not updated:
        raise HTTPException(status_code=404, detail="Task not found")
    GoogleCalendarService(db).sync_task_safely(str(user_id), updated)
    return updated


# ── DELETE /tasks/{task_id} ─────────────────────────────────────────────────
@router.delete("/{task_id}", status_code=204)
def delete_task(
    task_id: str,
    user_id: CurrentUserId,
):
    db = _require_db()
    svc = TaskService(db)
    GoogleCalendarService(db).delete_task_safely(str(user_id), task_id)
    deleted = svc.delete(str(user_id), task_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Task not found")
