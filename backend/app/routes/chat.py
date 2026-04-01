from fastapi import APIRouter, Header
from fastapi.responses import StreamingResponse
from typing import Optional

from ..schemas.chat import ChatRequest
from ..services.chat_service import ChatService
from ..db.supabase_client import get_supabase, is_supabase_configured
from .tasks import _get_user_id

router = APIRouter()


@router.post("")
async def chat(
    body: ChatRequest,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    """
    Stream an AI coach response from Ollama (Phi-3 Mini).
    Requires Ollama to be running locally with the phi3 model pulled.
    """
    user_id = _get_user_id(x_user_id, authorization)
    db      = get_supabase() if is_supabase_configured() else None
    svc     = ChatService(db)

    return StreamingResponse(
        svc.stream(user_id, body.message, [m.model_dump() for m in body.history]),
        media_type="text/event-stream",
        headers={
            "Cache-Control":    "no-cache",
            "Connection":       "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
