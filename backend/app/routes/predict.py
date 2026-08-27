from fastapi import APIRouter, HTTPException, Request

from ..config import settings
from ..dependencies.auth import CurrentUserId
from ..rate_limit import RateLimitSpec, get_request_identity, rate_limiter
from ..schemas.prediction import PredictRequest, PredictResponse
from ..services.ml_service import get_ml_service

router = APIRouter()


# ── POST /predict ────────────────────────────────────────────────────────────
@router.post("", response_model=PredictResponse)
def predict(
    body: PredictRequest,
    request: Request,
    user_id: CurrentUserId,
):
    """
    Run success probability + failure reason prediction.
    The verified Supabase user is used for per-user calibration when available.
    """
    ml = get_ml_service()
    if not ml.is_ready:
        raise HTTPException(
            status_code=503,
            detail=(
                "ML models are not loaded. Check that model artifacts exist "
                "and the server started correctly."
            ),
        )

    owned_user_id = str(user_id)
    identity = get_request_identity(request, owned_user_id)
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
            user_id=owned_user_id,
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail="Prediction failed.") from exc

    return result
