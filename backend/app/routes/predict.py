from fastapi import APIRouter, HTTPException, Header, Request
from typing import Optional

from ..config import settings
from ..rate_limit import RateLimitSpec, get_request_identity, rate_limiter
from ..schemas.prediction import PredictRequest, PredictResponse
from ..services.ml_service import get_ml_service
from .tasks import _get_user_id

router = APIRouter()


# ── POST /predict ────────────────────────────────────────────────────────────
@router.post("", response_model=PredictResponse)
def predict(
    body: PredictRequest,
    request: Request,
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    """
    Run success probability + failure reason prediction.
    Auth is optional — if user_id is provided (via body or header), per-user
    calibration is applied when available.
    """
    ml = get_ml_service()
    if not ml.is_ready:
        raise HTTPException(
            status_code=503,
            detail="ML models are not loaded. Check that model artifacts exist and the server started correctly.",
        )

    # Prefer user_id from body (explicit), then from auth header / X-User-Id
    user_id = body.user_id or _get_user_id(x_user_id, authorization)
    if user_id == "demo-user":
        user_id = None  # no personalization for demo

    identity = get_request_identity(request, user_id or "demo-user")
    rate_limiter.enforce(
        key=f"predict:{identity}",
        spec=RateLimitSpec(
            requests=settings.predict_requests_per_window,
            window_seconds=settings.rate_limit_window_seconds,
        ),
    )

    try:
        result = ml.predict(
            task_category=body.task_category,
            planned_start_time=body.planned_start_time,
            planned_date=body.planned_date,
            planned_duration_min=body.planned_duration_min,
            importance=body.importance,
            energy_level=body.energy_level,
            focus_level=body.focus_level,
            total_tasks_today=body.total_tasks_today,
            user_id=user_id,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")

    return result
