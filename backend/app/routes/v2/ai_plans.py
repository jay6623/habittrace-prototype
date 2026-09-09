"""V2 routes for plan inputs and their single outcomes."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status

from ...dependencies.ai_services import get_ai_outcome_service, get_ai_plan_service
from ...dependencies.auth import CurrentUserId
from ...schemas.ai_outcome import OutcomeCreate, OutcomeResponse
from ...schemas.ai_plan import PlanInputCreate, PlanInputResponse
from ...services.ai_outcome_service import AIOutcomeService
from ...services.ai_plan_service import AIPlanService

router = APIRouter()


@router.post("/plans", response_model=PlanInputResponse, status_code=status.HTTP_201_CREATED)
def create_plan(
    body: PlanInputCreate,
    user_id: CurrentUserId,
    service: Annotated[AIPlanService, Depends(get_ai_plan_service)],
):
    return service.create(user_id, body)


@router.get("/plans/{plan_input_id}", response_model=PlanInputResponse)
def get_plan(
    plan_input_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[AIPlanService, Depends(get_ai_plan_service)],
):
    return service.get(user_id, plan_input_id)


@router.post(
    "/plans/{plan_input_id}/outcome",
    response_model=OutcomeResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_outcome(
    plan_input_id: UUID,
    body: OutcomeCreate,
    user_id: CurrentUserId,
    service: Annotated[AIOutcomeService, Depends(get_ai_outcome_service)],
):
    return service.create(user_id, plan_input_id, body)
