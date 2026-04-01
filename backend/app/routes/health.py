from fastapi import APIRouter
from ..services.ml_service import get_ml_service
from ..db.supabase_client import is_supabase_configured

router = APIRouter(tags=["health"])


@router.get("/health")
def health():
    ml = get_ml_service()
    return {
        "status": "ok",
        "ml_models_loaded": ml.is_ready,
        "supabase_configured": is_supabase_configured(),
    }
