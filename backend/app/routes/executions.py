from fastapi import APIRouter, HTTPException, Header
from typing import Optional

from ..schemas.execution import ExecutionCreate, ExecutionResponse
from ..services.execution_service import ExecutionService
from ..db.supabase_client import get_supabase, is_supabase_configured
from .tasks import _get_user_id

router = APIRouter()


def _require_db():
    if not is_supabase_configured():
        raise HTTPException(
            status_code=503,
            detail="Database not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env",
        )
    return get_supabase()


# ── POST /executions ────────────────────────────────────────────────────────
@router.post("", response_model=ExecutionResponse, status_code=201)
def log_execution(
    body: ExecutionCreate,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = ExecutionService(db)
    result = svc.log(user_id, body.model_dump())
    return result


# ── GET /executions ─────────────────────────────────────────────────────────
@router.get("", response_model=list[ExecutionResponse])
def list_executions(
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = ExecutionService(db)
    return svc.list_for_user(user_id)
