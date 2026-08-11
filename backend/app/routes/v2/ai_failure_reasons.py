"""V2 route for active failure reason definitions."""
from typing import Annotated

from fastapi import APIRouter, Depends

from ...dependencies.ai_services import get_ai_failure_reason_service
from ...dependencies.auth import CurrentUserId
from ...schemas.ai_failure_reason import FailureReasonDefinitionResponse
from ...services.ai_failure_reason_service import AIFailureReasonService

router = APIRouter()


@router.get("/failure-reasons", response_model=list[FailureReasonDefinitionResponse])
def list_failure_reasons(
    _user_id: CurrentUserId,
    service: Annotated[
        AIFailureReasonService, Depends(get_ai_failure_reason_service)
    ],
):
    return service.list_active()
