"""AI-assisted time recommendation endpoints."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ...dependencies.ai_services import get_ai_time_recommendation_service
from ...dependencies.auth import CurrentUserId
from ...schemas.ai_time_recommendation import (
    TimeRecommendationCreate,
    TimeRecommendationResponse,
    TimeRecommendationSelect,
)
from ...services.ai_time_recommendation_service import AITimeRecommendationService

router = APIRouter()


@router.post(
    "/plans/{plan_input_id}/time-recommendations",
    response_model=TimeRecommendationResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_time_recommendation(
    plan_input_id: UUID,
    body: TimeRecommendationCreate,
    user_id: CurrentUserId,
    service: Annotated[
        AITimeRecommendationService, Depends(get_ai_time_recommendation_service)
    ],
) -> dict:
    try:
        return service.create(user_id, plan_input_id, body)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI time recommendation is temporarily unavailable.",
        ) from exc


@router.get(
    "/time-recommendations/{recommendation_id}",
    response_model=TimeRecommendationResponse,
)
def get_time_recommendation(
    recommendation_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[
        AITimeRecommendationService, Depends(get_ai_time_recommendation_service)
    ],
) -> dict:
    return service.get(user_id, recommendation_id)


@router.post(
    "/time-recommendations/{recommendation_id}/select",
    response_model=TimeRecommendationResponse,
)
def select_time_candidate(
    recommendation_id: UUID,
    body: TimeRecommendationSelect,
    user_id: CurrentUserId,
    service: Annotated[
        AITimeRecommendationService, Depends(get_ai_time_recommendation_service)
    ],
) -> dict:
    return service.select(user_id, recommendation_id, body)
