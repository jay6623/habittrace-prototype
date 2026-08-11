"""Aggregate router for the AI V2 API."""
from fastapi import APIRouter

from . import (
    ai_failure_reasons,
    ai_outcomes,
    ai_plans,
    ai_predict,
    ai_time_recommendations,
)

router = APIRouter(prefix="/api/v2/ai", tags=["ai-v2"])
router.include_router(ai_plans.router)
router.include_router(ai_outcomes.router)
router.include_router(ai_failure_reasons.router)
router.include_router(ai_predict.router)
router.include_router(ai_time_recommendations.router)
