"""Dependency factories for V2 AI services."""
from typing import Annotated

from fastapi import Depends
from supabase import Client

from ..repositories.ai_failure_reason_repository import AIFailureReasonRepository
from ..repositories.ai_outcome_repository import AIOutcomeRepository
from ..repositories.ai_plan_repository import AIPlanRepository
from ..repositories.ai_prediction_repository import AIPredictionRepository
from ..repositories.ai_time_recommendation_repository import (
    AITimeRecommendationRepository,
)
from ..services.ai_failure_reason_service import AIFailureReasonService
from ..services.ai_outcome_service import AIOutcomeService
from ..services.ai_plan_service import AIPlanService
from ..services.ai_prediction_service import AIPredictionService
from ..services.ai_time_recommendation_service import AITimeRecommendationService
from ..services.ai_v2_ml_service import get_ai_v2_ml_service
from .database import get_ai_database


def get_ai_plan_service(
    db: Annotated[Client, Depends(get_ai_database)],
) -> AIPlanService:
    return AIPlanService(AIPlanRepository(db))


def get_ai_outcome_service(
    db: Annotated[Client, Depends(get_ai_database)],
) -> AIOutcomeService:
    return AIOutcomeService(AIPlanRepository(db), AIOutcomeRepository(db))


def get_ai_failure_reason_service(
    db: Annotated[Client, Depends(get_ai_database)],
) -> AIFailureReasonService:
    return AIFailureReasonService(
        AIPlanRepository(db),
        AIOutcomeRepository(db),
        AIFailureReasonRepository(db),
    )


def get_ai_prediction_service(
    db: Annotated[Client, Depends(get_ai_database)],
) -> AIPredictionService:
    return AIPredictionService(
        AIPlanRepository(db),
        AIPredictionRepository(db),
        get_ai_v2_ml_service(),
    )


def get_ai_time_recommendation_service(
    db: Annotated[Client, Depends(get_ai_database)],
) -> AITimeRecommendationService:
    return AITimeRecommendationService(
        AIPlanRepository(db),
        AITimeRecommendationRepository(db),
        AIPredictionService(
            AIPlanRepository(db),
            AIPredictionRepository(db),
            get_ai_v2_ml_service(),
        ),
        get_ai_v2_ml_service(),
    )
