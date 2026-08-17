import logging
from fastapi import APIRouter, HTTPException, Header, Query
from typing import Optional

from ..schemas.analytics import AnalyticsSummary, PlanHealth
from ..services.analytics_service import AnalyticsService
from ..services.ml_service import get_ml_service
from ..db.supabase_client import get_supabase, is_supabase_configured
from .tasks import _get_user_id

logger = logging.getLogger(__name__)
router = APIRouter()


def _require_db():
    if not is_supabase_configured():
        raise HTTPException(
            status_code=503,
            detail="Database not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env",
        )
    return get_supabase()


# ── GET /analytics/summary ───────────────────────────────────────────────────
@router.get("/summary", response_model=AnalyticsSummary)
def analytics_summary(
    period: str = Query("week", pattern="^(week|month|3months)$"),
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = AnalyticsService(db)
    return svc.get_summary(user_id, period=period)


# ── GET /analytics/plan-health ───────────────────────────────────────────────
@router.get("/plan-health", response_model=PlanHealth)
def plan_health(
    x_user_id: Optional[str] = Header(None),
    authorization: Optional[str] = Header(None),
):
    user_id = _get_user_id(x_user_id, authorization)
    db = _require_db()
    svc = AnalyticsService(db)
    health = svc.get_plan_health(user_id)

    # ── Enhance with ML predictions ────────────────────────────────────────
    ml = get_ml_service()
    if ml.is_ready and health["task_count"] > 0:
        probabilities: list[float] = []
        total_tasks = health["task_count"]

        for task_summary in health["tasks"]:
            # Find the original task data (we need energy/focus/importance)
            from datetime import date
            today = date.today().isoformat()
            task_rows = (
                db.table("tasks")
                .select("*")
                .eq("id", task_summary["id"])
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
                    user_id=user_id,
                )
                p = pred["success_probability"]
                task_summary["predicted_success"] = round(p, 4)
                probabilities.append(p)

                # Add risk for tasks with very low ML-predicted probability
                if t.get("task_status") == "pending" and p < 0.45:
                    reason = pred.get("predicted_failure_reason") or ""
                    health["risks"].append({
                        "level": "high" if p < 0.3 else "medium",
                        "title": f"Low success: {t.get('title', 'Task')[:30]}",
                        "detail": (
                            f"AI predicts {round(p * 100)}% success"
                            + (f" — likely cause: {reason.replace('_', ' ')}" if reason else "")
                        ),
                    })
            except Exception as exc:
                logger.warning("ML prediction failed for task %s: %s", task_summary["id"], exc)

        # Replace heuristic probability with ML average (pending tasks only)
        if probabilities:
            health["overall_success_probability"] = round(
                sum(probabilities) / len(probabilities), 2
            )

    return health
