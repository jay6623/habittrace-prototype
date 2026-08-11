"""V2 routes for post-execution failure feedback."""
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status

from ...dependencies.ai_services import get_ai_failure_reason_service
from ...dependencies.auth import CurrentUserId
from ...schemas.ai_failure_reason import FailureReasonCreate, FailureReasonSetResponse
from ...services.ai_failure_reason_service import AIFailureReasonService

router = APIRouter()


@router.post(
    "/outcomes/{outcome_id}/failure-reasons",
    response_model=FailureReasonSetResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_failure_reasons(
    outcome_id: UUID,
    body: FailureReasonCreate,
    user_id: CurrentUserId,
    service: Annotated[
        AIFailureReasonService, Depends(get_ai_failure_reason_service)
    ],
):
    return service.create_for_outcome(user_id, outcome_id, body)
