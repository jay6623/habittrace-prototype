import logging
from datetime import date
from typing import Annotated
from zoneinfo import ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Query
from supabase import Client

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..dependencies.database import get_primary_database
from ..repositories.personalization_repository import PersonalizationRepository
from ..schemas.analytics import (
    AnalyticsSummary,
    PersonalizedInsights,
    PersonalizedOutlook,
    PlanHealth,
)
from ..services.analytics_service import AnalyticsService
from ..services.ai_v2_ml_service import get_ai_v2_ml_service
from ..services.ml_service import get_ml_service
from ..services.personalization_service import PersonalizationService
from ..services.personalized_insights_service import PersonalizedInsightsService
from ..services.personalized_outlook_service import PersonalizedOutlookService

logger = logging.getLogger(__name__)
router = APIRouter()


def _require_db():
    if not is_supabase_configured():
        raise HTTPException(
            status_code=503,
            detail=(
                "Database not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env"
            ),
        )
    return get_supabase()


# ── GET /analytics/summary ───────────────────────────────────────────────────
@router.get("/summary", response_model=AnalyticsSummary)
def analytics_summary(
    user_id: CurrentUserId,
    period: str = Query("week", pattern="^(week|month|3months)$"),
):
    db = _require_db()
    svc = AnalyticsService(db)
    return svc.get_summary(str(user_id), period=period)


@router.get("/personalized-outlook", response_model=PersonalizedOutlook)
def personalized_outlook(
    user_id: CurrentUserId,
    db: Annotated[Client, Depends(get_primary_database)],
    planned_date: date | None = Query(default=None, alias="date"),
    timezone_name: str = Query(default="UTC", min_length=1, max_length=100),
):
    service = PersonalizedOutlookService(
        db,
        get_ai_v2_ml_service(),
        PersonalizationService(PersonalizationRepository(db)),
    )
    try:
        return service.get(user_id, planned_date or date.today(), timezone_name)
    except ZoneInfoNotFoundError as exc:
        raise HTTPException(status_code=422, detail="Unknown timezone_name.") from exc


@router.get("/personalized-insights", response_model=PersonalizedInsights)
def personalized_insights(
    user_id: CurrentUserId,
    db: Annotated[Client, Depends(get_primary_database)],
    period: str = Query("week", pattern="^(week|month|3months)$"),
    end_date: date | None = Query(default=None),
):
    service = PersonalizedInsightsService(PersonalizationRepository(db))
    return service.get(user_id, period, end_date or date.today())


# ── GET /analytics/plan-health ───────────────────────────────────────────────
@router.get("/plan-health", response_model=PlanHealth)
def plan_health(
    user_id: CurrentUserId,
):
    owned_user_id = str(user_id)
    db = _require_db()
    svc = AnalyticsService(db)
    health = svc.get_plan_health(owned_user_id)

    # ── Enhance with ML predictions ────────────────────────────────────────
    ml = get_ml_service()
    if ml.is_ready and health["task_count"] > 0:
        probabilities: list[float] = []
        total_tasks = health["task_count"]

        for task_summary in health["tasks"]:
            # Find the original task data (we need energy/focus/importance)
            task_rows = (
                db.table("tasks")
                .select("*")
                .eq("id", task_summary["id"])
                .eq("user_id", owned_user_id)
                .execute()
            ).data
            if not task_rows:
                continue
            t = task_rows[0]

            try:
                pred = ml.predict(
                    task_category=t.get("task_category", "Other"),
                    planned_start_time=t.get("planned_start_time", "12:00 PM"),
                    planned_date=t.get("planned_date"),
                    planned_duration_min=t.get("planned_duration_min", 60),
                    importance=t.get("importance", 3),
                    energy_level=t.get("energy_level", 3),
                    focus_level=t.get("focus_level", 3),
                    total_tasks_today=total_tasks,
                    user_id=owned_user_id,
                )
                p = pred["success_probability"]
                task_summary["predicted_success"] = round(p, 4)
                probabilities.append(p)

                # Add risk for tasks with very low ML-predicted probability
                if t.get("task_status") == "pending" and p < 0.45:
                    reason = pred.get("predicted_failure_reason") or ""
                    health["risks"].append(
                        {
                            "level": "high" if p < 0.3 else "medium",
                            "title": f"Low success: {t.get('title', 'Task')[:30]}",
                            "detail": (
                                f"AI predicts {round(p * 100)}% success"
                                + (f" — likely cause: {reason.replace('_', ' ')}" if reason else "")
                            ),
                        }
                    )
            except Exception as exc:
                logger.warning("ML prediction failed for task %s: %s", task_summary["id"], exc)

        # Replace heuristic probability with ML average (pending tasks only)
        if probabilities:
            health["overall_success_probability"] = round(
                sum(probabilities) / len(probabilities), 2
            )

    return health
