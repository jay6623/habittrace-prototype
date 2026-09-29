"""Draft-first daily schedule generation endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ...dependencies.ai_services import get_daily_schedule_service
from ...dependencies.auth import CurrentUserId
from ...schemas.daily_schedule import (
    DailyScheduleGenerate,
    DailyScheduleResponse,
    DailyScheduleUpdate,
)
from ...services.daily_schedule_service import DailyScheduleService

router = APIRouter(prefix="/daily-schedules")


@router.post(
    "/generate",
    response_model=DailyScheduleResponse,
    status_code=status.HTTP_201_CREATED,
)
def generate_daily_schedule(
    body: DailyScheduleGenerate,
    user_id: CurrentUserId,
    service: Annotated[DailyScheduleService, Depends(get_daily_schedule_service)],
) -> dict:
    try:
        return service.generate(user_id, body)
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Daily schedule generation is temporarily unavailable.",
        ) from exc


@router.get("/{schedule_id}", response_model=DailyScheduleResponse)
def get_daily_schedule(
    schedule_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[DailyScheduleService, Depends(get_daily_schedule_service)],
) -> dict:
    return service.get(user_id, schedule_id)


@router.patch("/{schedule_id}", response_model=DailyScheduleResponse)
def update_daily_schedule(
    schedule_id: UUID,
    body: DailyScheduleUpdate,
    user_id: CurrentUserId,
    service: Annotated[DailyScheduleService, Depends(get_daily_schedule_service)],
) -> dict:
    return service.update(user_id, schedule_id, body)


@router.post("/{schedule_id}/confirm", response_model=DailyScheduleResponse)
def confirm_daily_schedule(
    schedule_id: UUID,
    user_id: CurrentUserId,
    service: Annotated[DailyScheduleService, Depends(get_daily_schedule_service)],
) -> dict:
    return service.confirm(user_id, schedule_id)
