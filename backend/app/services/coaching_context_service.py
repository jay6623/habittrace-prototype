"""User-owned coaching analytics and compact prompt context."""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any, cast
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from supabase import Client

from .analytics_service import _hour_from_time_str

MAX_TOOL_QUERY_ROWS = 200
MAX_SCHEDULE_RESULTS = 50


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

    @staticmethod
    def _today(timezone_name: str) -> date:
        try:
            return datetime.now(ZoneInfo(timezone_name)).date()
        except ZoneInfoNotFoundError:
            return datetime.now(ZoneInfo("UTC")).date()

    def _task_rows(
        self,
        user_id: str,
        *,
        start_date: date,
        end_date: date,
        category: str | None = None,
        title_query: str | None = None,
    ) -> list[dict[str, Any]]:
        query = (
            self.db.table("tasks")
            .select(
                "id,title,task_category,task_status,planned_date,planned_start_time,"
                "planned_duration_min"
            )
            .eq("user_id", user_id)
            .gte("planned_date", start_date.isoformat())
            .lte("planned_date", end_date.isoformat())
        )
        if category:
            query = query.eq("task_category", category)
        rows = cast(
            list[dict[str, Any]],
            list(query.limit(MAX_TOOL_QUERY_ROWS).execute().data or []),
        )
        if title_query:
            needle = title_query.casefold().strip()
            rows = [row for row in rows if needle in str(row.get("title") or "").casefold()]
        # Keep the bound even when a test double or provider ignores limit().
        return rows[:MAX_TOOL_QUERY_ROWS]

    @staticmethod
    def _performance_summary(tasks: list[dict[str, Any]]) -> dict[str, Any]:
        completed = [task for task in tasks if task.get("task_status") in {"success", "failed"}]
        successes = sum(task.get("task_status") == "success" for task in completed)
        durations = [int(task.get("planned_duration_min") or 0) for task in completed]
        return {
            "successful_tasks": successes,
            "failed_tasks": len(completed) - successes,
            "success_rate": _rate(successes, len(completed)),
            "sample_size": len(completed),
            "average_planned_minutes": round(sum(durations) / len(durations), 1)
            if durations
            else None,
        }

    def get_task_performance(
        self,
        user_id: str,
        *,
        timezone_name: str = "UTC",
        category: str | None = None,
        title_query: str | None = None,
        period_days: int = 30,
        compare_previous_period: bool = False,
        group_by: list[str] | None = None,
    ) -> dict[str, Any]:
        """Return bounded outcome statistics for only the requested task scope."""
        period_days = max(7, min(90, int(period_days)))
        today = self._today(timezone_name)
        current_start = today - timedelta(days=period_days - 1)
        query_start = (
            current_start - timedelta(days=period_days)
            if compare_previous_period
            else current_start
        )
        tasks = self._task_rows(
            user_id,
            start_date=query_start,
            end_date=today,
            category=category,
            title_query=title_query,
        )
        current = [
            task
            for task in tasks
            if str(task.get("planned_date") or "") >= current_start.isoformat()
        ]
        result: dict[str, Any] = {
            "scope": {"category": category, "title_query": title_query},
            "period": {
                "start": current_start.isoformat(),
                "end": today.isoformat(),
                "days": period_days,
            },
            "current": self._performance_summary(current),
            "data_notes": ["Rates with fewer than 5 observations have low confidence."],
        }
        if compare_previous_period:
            previous_end = current_start - timedelta(days=1)
            previous_start = previous_end - timedelta(days=period_days - 1)
            previous = [
                task
                for task in tasks
                if previous_start.isoformat()
                <= str(task.get("planned_date") or "")
                <= previous_end.isoformat()
            ]
            current_rate = result["current"]["success_rate"]
            previous_summary = self._performance_summary(previous)
            previous_rate = previous_summary["success_rate"]
            result["previous"] = {
                "period": {"start": previous_start.isoformat(), "end": previous_end.isoformat()},
                **previous_summary,
            }
            result["success_rate_change_points"] = (
                round(float(current_rate) - float(previous_rate), 1)
                if current_rate is not None and previous_rate is not None
                else None
            )

        completed = [
            task for task in current if task.get("task_status") in {"success", "failed"}
        ]
        requested_groups = set(group_by or [])
        if "hour" in requested_groups:
            hour_groups: dict[int, list[dict]] = defaultdict(list)
            for task in completed:
                hour_groups[
                    _hour_from_time_str(str(task.get("planned_start_time") or "12:00"))
                ].append(task)
            result["by_hour"] = [
                {"hour": hour, **self._performance_summary(group)}
                for hour, group in sorted(hour_groups.items())
            ]
        if "weekday" in requested_groups:
            weekday_groups: dict[str, list[dict]] = defaultdict(list)
            for task in completed:
                try:
                    weekday = date.fromisoformat(str(task.get("planned_date"))).strftime("%A")
                except (TypeError, ValueError):
                    continue
                weekday_groups[weekday].append(task)
            result["by_weekday"] = [
                {"weekday": weekday, **self._performance_summary(group)}
                for weekday, group in sorted(weekday_groups.items())
            ]
        return result

    def get_failure_patterns(
        self,
        user_id: str,
        *,
        timezone_name: str = "UTC",
        category: str | None = None,
        title_query: str | None = None,
        period_days: int = 30,
    ) -> dict[str, Any]:
        """Return failure evidence joined only to tasks in the requested scope."""
        period_days = max(7, min(90, int(period_days)))
        today = self._today(timezone_name)
        start = today - timedelta(days=period_days - 1)
        tasks = self._task_rows(
            user_id,
            start_date=start,
            end_date=today,
            category=category,
            title_query=title_query,
        )
        tasks_by_id = {str(task.get("id")): task for task in tasks}
        if tasks_by_id:
            raw_execution_rows = list(
                (
                    self.db.table("executions")
                    .select(
                        "task_id,task_status,failure_reason,interruption_count,"
                        "actual_start_time,actual_end_time,created_at"
                    )
                    .eq("user_id", user_id)
                    .in_("task_id", list(tasks_by_id))
                    .gte("created_at", start.isoformat())
                    .limit(MAX_TOOL_QUERY_ROWS)
                    .execute()
                ).data
                or []
            )[:MAX_TOOL_QUERY_ROWS]
            rows = cast(list[dict[str, Any]], raw_execution_rows)
        else:
            rows = []
        executions = [row for row in rows if str(row.get("task_id")) in tasks_by_id]
        failed = [row for row in executions if row.get("task_status") == "failed"]
        reasons = Counter(
            str(row["failure_reason"]) for row in failed if row.get("failure_reason")
        )
        interruptions = [int(row.get("interruption_count") or 0) for row in executions]
        duration_deltas: list[int] = []
        for execution in executions:
            started = _parse_timestamp(execution.get("actual_start_time"))
            ended = _parse_timestamp(execution.get("actual_end_time"))
            task = tasks_by_id[str(execution.get("task_id"))]
            if started and ended:
                actual_minutes = int((ended - started).total_seconds() // 60)
                duration_deltas.append(actual_minutes - int(task.get("planned_duration_min") or 0))
        return {
            "scope": {"category": category, "title_query": title_query},
            "period": {"start": start.isoformat(), "end": today.isoformat(), "days": period_days},
            "matched_tasks": len(tasks),
            "failed_executions": len(failed),
            "failure_reasons": [
                {"reason": reason, "count": count} for reason, count in reasons.most_common(5)
            ],
            "average_interruptions": round(sum(interruptions) / len(interruptions), 1)
            if interruptions
            else None,
            "average_actual_minus_planned_minutes": round(
                sum(duration_deltas) / len(duration_deltas), 1
            )
            if duration_deltas
            else None,
            "data_notes": ["Recorded patterns are correlations, not proven causes."],
        }

    def get_schedule(self, user_id: str, *, start_date: date, end_date: date) -> dict[str, Any]:
        """Return a bounded window of pending tasks without loading historical analytics."""
        if end_date < start_date or (end_date - start_date).days > 31:
            raise ValueError("Schedule range must be ordered and no longer than 31 days.")
        tasks = self._task_rows(user_id, start_date=start_date, end_date=end_date)
        all_scheduled = sorted(
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
            ],
            key=lambda item: (str(item["date"]), str(item["time"])),
        )
        scheduled = all_scheduled[:MAX_SCHEDULE_RESULTS]
        return {
            "range": {"start": start_date.isoformat(), "end": end_date.isoformat()},
            "tasks": scheduled,
            "result_count": len(scheduled),
            "truncated": len(all_scheduled) > MAX_SCHEDULE_RESULTS,
        }

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
                if execution.get("task_status") == "failed" and execution.get("failure_reason")
            )
            category_interruptions = [
                int(execution.get("interruption_count") or 0) for execution in category_executions
            ]
            planned_durations = [int(task.get("planned_duration_min") or 0) for task in group]
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
        category_patterns.sort(key=lambda item: (-item["sample_size"], str(item["category"])))

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
