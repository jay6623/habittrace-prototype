from fastapi import APIRouter

from ..db.supabase_client import (
    is_ai_supabase_configured,
    is_auth_supabase_configured,
    is_supabase_configured,
)
from ..services.ai_v2_ml_service import get_ai_v2_ml_service
from ..services.ml_service import get_ml_service

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    ml = get_ml_service()
    ai_v2_ready = get_ai_v2_ml_service().is_ready
    configured = {
        "supabase_configured": is_supabase_configured(),
        "ai_supabase_configured": is_ai_supabase_configured(),
        "auth_supabase_configured": is_auth_supabase_configured(),
    }
    ready = all(configured.values()) and ai_v2_ready
    return {
        "status": "ok" if ready else "degraded",
        "ready": ready,
        "ml_models_loaded": ml.is_ready,
        "ai_v2_models_loaded": ai_v2_ready,
        **configured,
    }
