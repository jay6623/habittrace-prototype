"""XP and level progress for the signed-in user."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from supabase import Client

from ..dependencies.auth import CurrentUserId
from ..dependencies.database import get_primary_database
from ..repositories.gamification_repository import GamificationRepository
from ..schemas.gamification import XpSummary
from ..services.gamification_service import GamificationService
from ..utils.timezone import get_timezone

router = APIRouter()


@router.get("/summary", response_model=XpSummary)
def xp_summary(
    user_id: CurrentUserId,
    db: Annotated[Client, Depends(get_primary_database)],
    timezone_name: Annotated[str, Query(alias="timezone", min_length=1, max_length=100)] = "UTC",
):
    try:
        today = datetime.now(get_timezone(timezone_name)).date()
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Unknown timezone.") from exc
    return GamificationService(GamificationRepository(db)).get_summary(user_id, today)
