"""V2 model inference endpoint."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ...dependencies.ai_services import get_ai_prediction_service
from ...dependencies.auth import CurrentUserId
from ...schemas.ai_prediction import AIPredictRequest, AIPredictResponse, prediction_payload
from ...services.ai_prediction_service import AIPredictionService
from ...services.ai_v2_ml_service import AIV2MLService, get_ai_v2_ml_service

router = APIRouter()


@router.get("/plans/{plan_input_id}/prediction", response_model=dict)
def latest_owned_prediction(
    plan_input_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[AIPredictionService, Depends(get_ai_prediction_service)],
) -> dict:
    prediction = service.latest_for_plan(user_id, plan_input_id)
    return {"prediction": prediction}


@router.post("/plans/{plan_input_id}/predict", response_model=dict)
def predict_owned_plan(
    plan_input_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[AIPredictionService, Depends(get_ai_prediction_service)],
) -> dict:
    try:
        return service.predict_for_plan(user_id, plan_input_id)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI V2 prediction persistence is temporarily unavailable.",
        ) from exc


@router.post("/predict", response_model=AIPredictResponse)
def predict(
    body: AIPredictRequest,
    _user_id: CurrentUserId,
    service: Annotated[AIV2MLService, Depends(get_ai_v2_ml_service)],
) -> dict:
    if not service.is_ready:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI V2 model artifacts are not loaded.",
        )
    try:
        return service.predict(prediction_payload(body))
    except (ValueError, TypeError, RuntimeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI V2 prediction is temporarily unavailable.",
        ) from exc
