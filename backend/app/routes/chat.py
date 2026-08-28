from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import StreamingResponse

from ..config import settings
from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..rate_limit import RateLimitSpec, get_request_identity, rate_limiter
from ..schemas.chat import ChatRequest, ProposalConfirmRequest
from ..schemas.task import TaskCreate, TaskResponse
from ..services.chat_service import ChatService
from ..services.coach_repository import CoachRepository
from ..services.task_service import TaskService

router = APIRouter()


@router.post("")
async def chat(
    body: ChatRequest,
    request: Request,
    user_id: CurrentUserId,
):
    """
    Stream database-aware coaching text and typed action proposals from Ollama.
    """
    owned_user_id = str(user_id)
    identity = get_request_identity(request, owned_user_id)
    rate_limiter.enforce(
        key=f"chat:{identity}",
        spec=RateLimitSpec(
            requests=settings.chat_requests_per_window,
            window_seconds=settings.rate_limit_window_seconds,
        ),
    )

    db = get_supabase() if is_supabase_configured() else None
    svc = ChatService(db)

    return StreamingResponse(
        svc.stream(
            owned_user_id,
            body.message,
            [m.model_dump() for m in body.history],
            conversation_id=body.conversation_id,
            timezone_name=body.timezone_name,
        ),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.get("/conversations/latest")
def latest_conversation(user_id: CurrentUserId):
    if not is_supabase_configured():
        return None
    try:
        return ChatService(get_supabase()).latest_conversation(str(user_id))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Coach persistence is unavailable. Apply the coach agent database migration.",
        ) from exc


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
def archive_conversation(conversation_id: UUID, user_id: CurrentUserId):
    if not is_supabase_configured():
        raise HTTPException(status_code=503, detail="Database is not configured.")
    try:
        archived = ChatService(get_supabase()).archive_conversation(conversation_id, str(user_id))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Coach persistence is unavailable.") from exc
    if not archived:
        raise HTTPException(status_code=404, detail="Conversation not found.")


@router.post("/proposals/{proposal_id}/confirm", response_model=TaskResponse)
def confirm_proposal(
    proposal_id: UUID,
    body: ProposalConfirmRequest,
    user_id: CurrentUserId,
):
    if not is_supabase_configured():
        raise HTTPException(status_code=503, detail="Database is not configured.")
    db = get_supabase()
    repo = CoachRepository(db)
    proposal = repo.get_owned_proposal(proposal_id, str(user_id))
    if not proposal:
        raise HTTPException(status_code=404, detail="Proposal not found.")
    if proposal.get("status") == "confirmed" and proposal.get("result"):
        return proposal["result"]
    if proposal.get("status") != "pending":
        raise HTTPException(status_code=409, detail="Proposal is no longer pending.")
    expires_at = datetime.fromisoformat(str(proposal["expires_at"]).replace("Z", "+00:00"))
    if expires_at < datetime.now(timezone.utc):
        repo.finish_proposal(proposal_id, str(user_id), "expired")
        raise HTTPException(status_code=409, detail="Proposal has expired.")

    payload = proposal.get("payload") or {}
    task_data = dict(payload.get("task") or {})
    options = payload.get("options") or []
    if body.candidate_start:
        selected = next(
            (item for item in options if item.get("start") == body.candidate_start),
            None,
        )
        if not selected:
            raise HTTPException(
                status_code=400, detail="Selected time is not part of this proposal."
            )
        selected_start = datetime.fromisoformat(str(selected["start"]).replace("Z", "+00:00"))
        task_data["planned_date"] = selected_start.date().isoformat()
        task_data["planned_start_time"] = selected_start.strftime("%H:%M")
    if body.task is not None:
        task_data.update(body.task.model_dump())

    validated = TaskCreate.model_validate(task_data)
    same_day = TaskService(db).list_for_user(str(user_id), validated.planned_date)
    validated.total_tasks_today = len(same_day) + 1
    created = TaskService(db).create(str(user_id), validated.model_dump())
    repo.finish_proposal(proposal_id, str(user_id), "confirmed", created)
    return created


@router.post("/proposals/{proposal_id}/dismiss", status_code=status.HTTP_204_NO_CONTENT)
def dismiss_proposal(proposal_id: UUID, user_id: CurrentUserId):
    if not is_supabase_configured():
        raise HTTPException(status_code=503, detail="Database is not configured.")
    repo = CoachRepository(get_supabase())
    proposal = repo.get_owned_proposal(proposal_id, str(user_id))
    if not proposal:
        raise HTTPException(status_code=404, detail="Proposal not found.")
    if proposal.get("status") == "pending":
        repo.finish_proposal(proposal_id, str(user_id), "dismissed")
