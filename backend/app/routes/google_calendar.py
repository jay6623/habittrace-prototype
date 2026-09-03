from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..schemas.google_calendar import (
    GoogleCalendarConnect,
    GoogleCalendarConnectResult,
    GoogleCalendarStatus,
    GoogleCalendarSyncResult,
)
from ..services.google_calendar_service import (
    GoogleCalendarError,
    GoogleCalendarService,
)

router = APIRouter()


def get_google_calendar_service() -> GoogleCalendarService:
    if not is_supabase_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Primary database is not configured.",
        )
    return GoogleCalendarService(get_supabase())


GoogleCalendarServiceDep = Annotated[
    GoogleCalendarService, Depends(get_google_calendar_service)
]


@router.get("/status", response_model=GoogleCalendarStatus)
def calendar_status(
    user_id: CurrentUserId,
    service: GoogleCalendarServiceDep,
):
    return service.status(str(user_id))


@router.post("/connect", response_model=GoogleCalendarConnectResult)
def connect_calendar(
    body: GoogleCalendarConnect,
    user_id: CurrentUserId,
    service: GoogleCalendarServiceDep,
):
    try:
        service.connect(
            str(user_id),
            body.provider_token,
            body.provider_refresh_token,
            body.timezone,
        )
        sync_result = service.sync_all(str(user_id))
        return {"status": service.status(str(user_id)), "sync": sync_result}
    except GoogleCalendarError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/sync", response_model=GoogleCalendarSyncResult)
def sync_calendar(
    user_id: CurrentUserId,
    service: GoogleCalendarServiceDep,
):
    try:
        return service.sync_all(str(user_id))
    except GoogleCalendarError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.delete("", status_code=204)
def disconnect_calendar(
    user_id: CurrentUserId,
    service: GoogleCalendarServiceDep,
):
    service.disconnect(str(user_id))
