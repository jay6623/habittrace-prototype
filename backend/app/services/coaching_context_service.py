"""User-owned coaching analytics and compact prompt context."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from supabase import Client

from .analytics_service import _hour_from_time_str


def _rate(successes: int, total: int) -> float | None:
    return round(successes / total * 100, 1) if total else None


def _parse_timestamp(value: object) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


class CoachingContextService:
    """Compute facts in Python so the language model never invents statistics."""

    def __init__(self, db: Client) -> None:
        self.db = db

    def get_preferences(self, user_id: str, timezone_name: str = "UTC") -> dict[str, Any]:
        defaults: dict[str, Any] = {
            "timezone_name": timezone_name,
            "preferred_day_start": "08:00",
            "preferred_day_end": "22:00",
            "minimum_buffer_minutes": 15,
            "coaching_style": "supportive",
        }
        try:
            result = (
                self.db.table("user_coaching_preferences")
                .select("*")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
            if result.data:
                defaults.update({k: v for k, v in result.data[0].items() if v is not None})
        except Exception:
            # The chat remains usable before the optional coach migration is applied.
            pass
        defaults["timezone_name"] = timezone_name or defaults["timezone_name"]
        return defaults

    def save_preferences(self, user_id: str, updates: dict[str, Any], timezone_name: str) -> dict:
        payload = {
            "user_id": user_id,
            "timezone_name": timezone_name,
            **{k: v for k, v in updates.items() if v is not None},
            "updated_at": datetime.now().astimezone().isoformat(),
        }
        result = (
            self.db.table("user_coaching_preferences")
            .upsert(payload, on_conflict="user_id")
            .execute()
        )
        return result.data[0] if result.data else payload

    def build(
        self,
        user_id: str,
        timezone_name: str = "UTC",
        through_date: str | None = None,
    ) -> dict[str, Any]:
        try:
            user_timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            user_timezone = ZoneInfo("UTC")
        today = datetime.now(user_timezone).date()
        start_90 = (today - timedelta(days=90)).isoformat()
        future_end = (today + timedelta(days=14)).isoformat()
        if through_date and through_date > future_end:
            future_end = through_date

        tasks = list(
            (
                self.db.table("tasks")
                .select("*")
                .eq("user_id", user_id)
                .gte("planned_date", start_90)
                .lte("planned_date", future_end)
                .execute()
            ).data
            or []
        )
        executions = list(
            (
                self.db.table("executions")
                .select("*")
                .eq("user_id", user_id)
                .gte("created_at", start_90)
                .execute()
            ).data
            or []
        )

        historical = [
            task
            for task in tasks
            if task.get("task_status") in {"success", "failed"}
            and str(task.get("planned_date") or "") <= today.isoformat()
        ]
        recent_30 = [
            task
            for task in historical
            if str(task.get("planned_date") or "") >= (today - timedelta(days=30)).isoformat()
        ]

        overall_success = sum(task.get("task_status") == "success" for task in recent_30)
        hour_groups: dict[int, list[dict]] = defaultdict(list)
        weekday_groups: dict[str, list[dict]] = defaultdict(list)
        category_groups: dict[str, list[dict]] = defaultdict(list)
        for task in historical:
            hour_groups[_hour_from_time_str(str(task.get("planned_start_time") or "12:00"))].append(
                task
            )
            category_groups[str(task.get("task_category") or "Other")].append(task)
            try:
                weekday = date.fromisoformat(str(task["planned_date"])).strftime("%A")
                weekday_groups[weekday].append(task)
            except (KeyError, TypeError, ValueError):
                pass

        def patterns(groups: dict[Any, list[dict]], key_name: str) -> list[dict]:
            rows = []
            for key, group in groups.items():
                successes = sum(item.get("task_status") == "success" for item in group)
                rows.append(
                    {
                        key_name: key,
                        "success_rate": _rate(successes, len(group)),
                        "sample_size": len(group),
                    }
                )
            return sorted(rows, key=lambda item: (-item["sample_size"], str(item[key_name])))

        executions_by_task: dict[str, list[dict]] = defaultdict(list)
        for execution in executions:
            executions_by_task[str(execution.get("task_id"))].append(execution)

        category_patterns = []
        for category, group in category_groups.items():
            successes = sum(item.get("task_status") == "success" for item in group)
            category_executions = [
                execution
                for task in group
                for execution in executions_by_task.get(str(task.get("id")), [])
            ]
            category_failure_reasons = Counter(
                str(execution["failure_reason"])
                for execution in category_executions
                if execution.get("task_status") == "failed"
                and execution.get("failure_reason")
            )
            category_interruptions = [
                int(execution.get("interruption_count") or 0)
                for execution in category_executions
            ]
            planned_durations = [
                int(task.get("planned_duration_min") or 0) for task in group
            ]
            category_patterns.append(
                {
                    "category": category,
                    "success_rate": _rate(successes, len(group)),
                    "successful_tasks": successes,
                    "failed_tasks": len(group) - successes,
                    "sample_size": len(group),
                    "average_planned_minutes": round(
                        sum(planned_durations) / len(planned_durations), 1
                    ),
                    "average_interruptions": round(
                        sum(category_interruptions) / len(category_interruptions), 1
                    )
                    if category_interruptions
                    else None,
                    "failure_reasons": [
                        {"reason": reason, "count": count}
                        for reason, count in category_failure_reasons.most_common(3)
                    ],
                }
            )
        category_patterns.sort(
            key=lambda item: (-item["sample_size"], str(item["category"]))
        )

        failure_reasons = Counter(
            str(row["failure_reason"])
            for row in executions
            if row.get("task_status") == "failed" and row.get("failure_reason")
        )
        interruptions = [int(row.get("interruption_count") or 0) for row in executions]
        duration_deltas: list[int] = []
        tasks_by_id = {str(task.get("id")): task for task in tasks}
        for execution in executions:
            started = _parse_timestamp(execution.get("actual_start_time"))
            ended = _parse_timestamp(execution.get("actual_end_time"))
            task = tasks_by_id.get(str(execution.get("task_id")))
            if started and ended and task:
                actual_minutes = int((ended - started).total_seconds() // 60)
                duration_deltas.append(actual_minutes - int(task.get("planned_duration_min") or 0))

        upcoming = sorted(
            [
                {
                    "id": task.get("id"),
                    "title": task.get("title"),
                    "category": task.get("task_category"),
                    "date": task.get("planned_date"),
                    "time": task.get("planned_start_time"),
                    "duration_minutes": task.get("planned_duration_min"),
                }
                for task in tasks
                if task.get("task_status") == "pending"
                and today.isoformat() <= str(task.get("planned_date") or "") <= future_end
            ],
            key=lambda item: (str(item["date"]), str(item["time"])),
        )

        return {
            "generated_on": today.isoformat(),
            "preferences": self.get_preferences(user_id, timezone_name),
            "last_30_days": {
                "completed_tasks": overall_success,
                "failed_tasks": len(recent_30) - overall_success,
                "success_rate": _rate(overall_success, len(recent_30)),
                "sample_size": len(recent_30),
            },
            "hour_patterns": patterns(hour_groups, "hour"),
            "weekday_patterns": patterns(weekday_groups, "weekday"),
            "category_patterns": category_patterns,
            "failure_reasons": [
                {"reason": reason, "count": count}
                for reason, count in failure_reasons.most_common(5)
            ],
            "average_interruptions": round(sum(interruptions) / len(interruptions), 1)
            if interruptions
            else None,
            "average_actual_minus_planned_minutes": round(
                sum(duration_deltas) / len(duration_deltas), 1
            )
            if duration_deltas
            else None,
            "upcoming_schedule": upcoming[:50],
            "data_notes": [
                "Treat patterns with fewer than 5 observations as low confidence.",
                "A missing rate means there is not enough recorded outcome data.",
            ],
        }
