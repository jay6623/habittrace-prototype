"""
Analytics aggregation — queries tasks + executions from Supabase
and returns chart-ready data for the frontend.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta

from supabase import Client

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _hour_from_time_str(time_str: str) -> int:
    """Parse a time string like '2:00 PM' or '14:00' into a 0-23 integer hour."""
    s = time_str.strip().upper()
    try:
        if "AM" in s or "PM" in s:
            for fmt in ("%I:%M %p", "%I:%M%p"):
                try:
                    from datetime import datetime

                    return datetime.strptime(s, fmt).hour
                except ValueError:
                    continue
        # 24-hour
        return int(s.split(":")[0])
    except Exception:
        return 12


def _hour_bucket(hour: int) -> str:
    if 6 <= hour < 9:
        return "6-9 AM"
    if 9 <= hour < 12:
        return "9-12 PM"
    if 12 <= hour < 15:
        return "12-3 PM"
    if 15 <= hour < 18:
        return "3-6 PM"
    if 18 <= hour < 21:
        return "6-9 PM"
    return "9-12 AM"


def _period_to_days(period: str) -> int:
    return {"week": 7, "month": 30, "3months": 90}.get(period, 7)


def _trend_labels_and_dates(period: str):
    """Return (labels, iso_dates) pairs for the given period."""
    from datetime import datetime

    today = date.today()
    if period == "week":
        days = [(today - timedelta(days=i)) for i in range(6, -1, -1)]
        labels = [d.strftime("%a") for d in days]
        iso = [d.isoformat() for d in days]
    elif period == "month":
        # 4 week buckets ending today
        labels, iso = [], []
        for i in range(3, -1, -1):
            start = today - timedelta(weeks=i + 1)
            labels.append(f"Week {4 - i}")
            iso.append(start.isoformat())  # representative date per bucket
        iso = None  # handled separately below
        return labels, None
    else:  # 3months
        labels = []
        iso = []
        for i in range(2, -1, -1):
            m = (today.month - i - 1) % 12 + 1
            y = today.year if today.month - i > 0 else today.year - 1
            from datetime import datetime

            labels.append(datetime(y, m, 1).strftime("%b"))
            iso.append(datetime(y, m, 1).date().isoformat())
    return labels, iso


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------


class AnalyticsService:
    def __init__(self, db: Client) -> None:
        self.db = db

    def get_summary(self, user_id: str, period: str = "week") -> dict:
        days = _period_to_days(period)
        since = (date.today() - timedelta(days=days - 1)).isoformat()

        # Fetch data
        tasks: list[dict] = (
            self.db.table("tasks")
            .select("*")
            .eq("user_id", user_id)
            .gte("planned_date", since)
            .execute()
        ).data

        execs: list[dict] = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .gte("created_at", since)
            .execute()
        ).data

        # ── Basic stats ─────────────────────────────────────────────────
        total = len(tasks)
        success_count = sum(1 for t in tasks if t.get("task_status") == "success")
        failed_tasks = [t for t in tasks if t.get("task_status") == "failed"]

        success_rate = (success_count / total * 100) if total > 0 else 0.0
        total_planned_mins = sum(t.get("planned_duration_min", 0) for t in tasks)
        avg_importance = (sum(t.get("importance", 0) for t in tasks) / total) if total > 0 else 0.0
        avg_interruptions = (
            (sum(e.get("interruption_count", 0) for e in execs) / len(execs)) if execs else 0.0
        )

        # ── Failure by category ─────────────────────────────────────────
        failure_by_category: dict[str, int] = defaultdict(int)
        for t in failed_tasks:
            failure_by_category[t.get("task_category", "Other")] += 1

        most_failed_category = (
            max(failure_by_category, key=failure_by_category.get) if failure_by_category else "N/A"
        )

        # ── Failure by reason ───────────────────────────────────────────
        failure_by_reason: dict[str, int] = defaultdict(int)
        for e in execs:
            if e.get("task_status") == "failed" and e.get("failure_reason"):
                failure_by_reason[e["failure_reason"]] += 1

        # ── Success by hour of day ──────────────────────────────────────
        hour_stats: dict[str, dict] = defaultdict(lambda: {"success": 0, "total": 0})
        for t in tasks:
            hour = _hour_from_time_str(t.get("planned_start_time", "12:00 PM"))
            bucket = _hour_bucket(hour)
            hour_stats[bucket]["total"] += 1
            if t.get("task_status") == "success":
                hour_stats[bucket]["success"] += 1

        success_by_hour = {
            bucket: round(v["success"] / v["total"] * 100, 1) if v["total"] > 0 else 0.0
            for bucket, v in hour_stats.items()
        }
        best_time = max(success_by_hour, key=success_by_hour.get) if success_by_hour else "N/A"

        # ── Execution trend (per day for week, simplified for longer) ───
        execution_trend = self._build_trend(tasks, period)

        return {
            "period": period,
            "total_tasks": total,
            "success_rate": round(success_rate, 1),
            "total_planned_minutes": total_planned_mins,
            "avg_importance": round(avg_importance, 1),
            "avg_interruptions": round(avg_interruptions, 1),
            "most_failed_category": most_failed_category,
            "best_time_of_day": best_time,
            "failure_by_category": dict(failure_by_category),
            "failure_by_reason": dict(failure_by_reason),
            "execution_trend": execution_trend,
            "success_by_hour": success_by_hour,
        }

    def _build_trend(self, tasks: list[dict], period: str) -> list[dict]:
        """Build per-period planned vs completed trend."""
        today = date.today()

        if period == "week":
            days = [(today - timedelta(days=i)) for i in range(6, -1, -1)]
            result = []
            for d in days:
                day_tasks = [t for t in tasks if t.get("planned_date") == d.isoformat()]
                planned = sum(t.get("planned_duration_min", 0) for t in day_tasks)
                completed = sum(
                    t.get("planned_duration_min", 0)
                    for t in day_tasks
                    if t.get("task_status") == "success"
                )
                total = len(day_tasks)
                success_rate = (
                    (sum(1 for t in day_tasks if t.get("task_status") == "success") / total * 100)
                    if total > 0
                    else 0.0
                )
                result.append(
                    {
                        "label": d.strftime("%a"),
                        "planned_mins": planned,
                        "completed_mins": completed,
                        "success_rate": round(success_rate, 1),
                    }
                )
            return result

        elif period == "month":
            result = []
            for week_num in range(4):
                end = today - timedelta(weeks=week_num)
                start = end - timedelta(days=6)
                week_tasks = [
                    t
                    for t in tasks
                    if start.isoformat() <= (t.get("planned_date") or "") <= end.isoformat()
                ]
                planned = sum(t.get("planned_duration_min", 0) for t in week_tasks)
                completed = sum(
                    t.get("planned_duration_min", 0)
                    for t in week_tasks
                    if t.get("task_status") == "success"
                )
                total = len(week_tasks)
                sr = (
                    (sum(1 for t in week_tasks if t.get("task_status") == "success") / total * 100)
                    if total > 0
                    else 0.0
                )
                result.insert(
                    0,
                    {
                        "label": f"Week {4 - week_num}",
                        "planned_mins": planned,
                        "completed_mins": completed,
                        "success_rate": round(sr, 1),
                    },
                )
            return result

        else:  # 3months
            result = []
            for i in range(2, -1, -1):
                month_date = date(today.year, today.month, 1) - timedelta(days=i * 30)
                month_tasks = [
                    t
                    for t in tasks
                    if (t.get("planned_date") or "").startswith(month_date.strftime("%Y-%m"))
                ]
                planned = sum(t.get("planned_duration_min", 0) for t in month_tasks)
                completed = sum(
                    t.get("planned_duration_min", 0)
                    for t in month_tasks
                    if t.get("task_status") == "success"
                )
                total = len(month_tasks)
                sr = (
                    (sum(1 for t in month_tasks if t.get("task_status") == "success") / total * 100)
                    if total > 0
                    else 0.0
                )
                result.append(
                    {
                        "label": month_date.strftime("%b"),
                        "planned_mins": planned,
                        "completed_mins": completed,
                        "success_rate": round(sr, 1),
                    }
                )
            return result

    def get_plan_health(self, user_id: str) -> dict:
        """Return aggregate predicted health for today's tasks (used by schedule-checker)."""
        today = date.today().isoformat()
        tasks: list[dict] = (
            self.db.table("tasks")
            .select("*")
            .eq("user_id", user_id)
            .eq("planned_date", today)
            .execute()
        ).data

        if not tasks:
            return {
                "overall_success_probability": 0.0,
                "task_count": 0,
                "risks": [],
            }

        # Check for common risk patterns
        risks = []
        late_tasks = [
            t for t in tasks if _hour_from_time_str(t.get("planned_start_time", "12:00")) >= 21
        ]
        if late_tasks:
            risks.append(
                {
                    "level": "high",
                    "title": "Late-night tasks",
                    "detail": f"{len(late_tasks)} task(s) planned after 9 PM — high failure risk",
                }
            )

        long_tasks = [t for t in tasks if t.get("planned_duration_min", 0) > 90]
        if long_tasks:
            risks.append(
                {
                    "level": "medium",
                    "title": "Very long tasks",
                    "detail": f"{len(long_tasks)} task(s) over 90 min — consider splitting",
                }
            )

        low_energy = [
            t
            for t in tasks
            if t.get("energy_level", 3) <= 2 and t.get("planned_duration_min", 0) > 45
        ]
        if low_energy:
            risks.append(
                {
                    "level": "medium",
                    "title": "Low energy + long task",
                    "detail": f"{len(low_energy)} task(s) flagged as low energy but long duration",
                }
            )

        total_mins = sum(t.get("planned_duration_min", 0) for t in tasks)
        if total_mins > 8 * 60:
            risks.append(
                {
                    "level": "low",
                    "title": "High daily load",
                    "detail": f"{total_mins} min planned — that's a very full day",
                }
            )

        # Rough heuristic probability based on task properties
        # (real probability comes from POST /predict per task)
        avg_energy = sum(t.get("energy_level", 3) for t in tasks) / len(tasks)
        has_late = len(late_tasks) > 0
        raw_prob = 0.65 + (avg_energy - 3) * 0.05 - (0.10 if has_late else 0)
        raw_prob = max(0.2, min(0.95, raw_prob))

        task_summaries = [
            {
                "id": t.get("id", ""),
                "title": t.get("title", ""),
                "task_category": t.get("task_category", "Other"),
                "task_status": t.get("task_status", "pending"),
                "planned_start_time": t.get("planned_start_time", ""),
                "planned_duration_min": t.get("planned_duration_min", 0),
                "predicted_success": None,  # filled in by route with ML
            }
            for t in tasks
        ]

        return {
            "overall_success_probability": round(raw_prob, 2),
            "task_count": len(tasks),
            "risks": risks,
            "tasks": task_summaries,
        }
