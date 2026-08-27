from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from ..config import settings
from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..rate_limit import RateLimitSpec, get_request_identity, rate_limiter
from ..schemas.chat import ChatRequest
from ..services.chat_service import ChatService

router = APIRouter()


@router.post("")
async def chat(
    body: ChatRequest,
    request: Request,
    user_id: CurrentUserId,
):
    """
    Stream an AI coach response from Ollama (Phi-3 Mini).
    Requires Ollama to be running locally with the phi3 model pulled.
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

    db      = get_supabase() if is_supabase_configured() else None
    svc     = ChatService(db)

    return StreamingResponse(
        svc.stream(owned_user_id, body.message, [m.model_dump() for m in body.history]),
        media_type="text/event-stream",
        headers={
            "Cache-Control":    "no-cache",
            "Connection":       "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
