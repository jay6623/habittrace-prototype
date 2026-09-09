from fastapi import APIRouter, HTTPException, Query

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..schemas.execution import (
    ExecutionComplete,
    ExecutionCreate,
    ExecutionResponse,
    ExecutionStart,
)
from ..services.execution_service import ExecutionService

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


# ── POST /executions ────────────────────────────────────────────────────────
@router.post("", response_model=ExecutionResponse, status_code=201)
def log_execution(
    body: ExecutionCreate,
    user_id: CurrentUserId,
):
    db = _require_db()
    svc = ExecutionService(db)
    result = svc.log(str(user_id), body.model_dump())
    if not result:
        raise HTTPException(status_code=404, detail="Task not found")
    return result


@router.post("/start", response_model=ExecutionResponse, status_code=201)
def start_execution(
    body: ExecutionStart,
    user_id: CurrentUserId,
):
    svc = ExecutionService(_require_db())
    try:
        result = svc.start(str(user_id), body.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    if not result:
        raise HTTPException(status_code=404, detail="Task not found")
    return result


@router.patch("/{execution_id}/complete", response_model=ExecutionResponse)
def complete_execution(
    execution_id: str,
    body: ExecutionComplete,
    user_id: CurrentUserId,
):
    svc = ExecutionService(_require_db())
    result = svc.complete(str(user_id), execution_id, body.model_dump())
    if not result:
        raise HTTPException(status_code=404, detail="Execution not found")
    return result


# ── GET /executions ─────────────────────────────────────────────────────────
@router.get("", response_model=list[ExecutionResponse])
def list_executions(
    user_id: CurrentUserId,
    active: bool = Query(False, description="Return only executions without an end time"),
):
    db = _require_db()
    svc = ExecutionService(db)
    if active:
        return svc.list_active_for_user(str(user_id))
    return svc.list_for_user(str(user_id))
