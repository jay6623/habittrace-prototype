"""Deterministic visualization of validated read-tool results; no database or LLM calls."""

from datetime import date, timedelta

from ..schemas.coach_chart import CoachChartSpec, VisualizationFocus
from ..schemas.coach_tools import GetFailurePatternsArgs, GetTaskPerformanceArgs

WEEKDAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


class CoachingVisualizationService:
    @staticmethod
    def _rate_point(label: str, summary: dict, minimum: int = 1) -> dict | None:
        total, successful, failed = (
            summary.get("sample_size"),
            summary.get("successful_tasks"),
            summary.get("failed_tasks"),
        )
        if (
            any(type(count) is not int for count in (total, successful, failed))
            or total < minimum
            or successful < 0
            or failed < 0
            or successful + failed != total
            or summary.get("success_rate") != round(successful / total * 100, 1)
        ):
            return None
        return {
            "label": label,
            "value": summary["success_rate"],
            "sample_size": total,
            "completed": successful,
        }

    @staticmethod
    def _weekly_points(result: dict) -> list[dict]:
        """Small weekly samples are descriptive evidence, provided all counts reconcile.

        Reject incomplete/malformed series rather than dropping their invalid buckets. Missing
        weeks are not buckets: the frontend displays a null gap, never a fabricated outcome.
        """
        weeks = result.get("by_week") or []
        period = result["period"]
        start, end = date.fromisoformat(period["start"]), date.fromisoformat(period["end"])
        first_week = start - timedelta(days=start.weekday())
        points = []
        successes = failures = 0
        for week in sorted(weeks, key=lambda row: row["date"]):
            day = date.fromisoformat(week["date"])
            point = CoachingVisualizationService._rate_point(day.isoformat(), week)
            if day.weekday() != 0 or not first_week <= day <= end or point is None:
                return []
            points.append(point)
            successes += week["successful_tasks"]
            failures += week["failed_tasks"]
        current = result.get("current") or {}
        if (
            CoachingVisualizationService._rate_point("Current", current) is None
            or len({point["label"] for point in points}) != len(points)
            or sum(point["sample_size"] for point in points) != current.get("sample_size")
            or successes != current.get("successful_tasks")
            or failures != current.get("failed_tasks")
        ):
            return []
        return points

    def build(
        self,
        tool_name: str,
        arguments: GetTaskPerformanceArgs | GetFailurePatternsArgs,
        result: dict,
        *,
        focus: VisualizationFocus | None = None,
    ) -> CoachChartSpec | None:
        """Tool grouping captures the question's intent from existing semantic selection.

        Comparative hour/day groups need five outcomes each. Descriptive weekly trends may
        include small samples when their counts reconcile with the full period summary.
        """
        if result.get("truncated"):
            return None
        rows = []
        chart_type = "bar"
        selected_focus = focus
        focus = None
        interval_days: int | None = None
        units = "percent"
        title = "Completion rate by weekday"
        x_axis = "Weekday"
        period = result.get("period") or {}
        note = "Recorded outcomes only; groups with fewer than 5 outcomes are omitted."
        if tool_name == "get_task_performance" and isinstance(arguments, GetTaskPerformanceArgs):
            start, end = date.fromisoformat(period["start"]), date.fromisoformat(period["end"])
            if (end - start).days + 1 != arguments.period_days:
                return None
            if "hour" in arguments.group_by:
                focus = "hour"
                rows = [
                    point
                    for row in sorted(result.get("by_hour", []), key=lambda row: row["hour"])
                    if (point := self._rate_point(f"{row['hour']:02d}:00", row, minimum=5))
                ]
                title, x_axis = "Completion rate by planned time of day", "Planned hour (local)"
            elif "weekday" in arguments.group_by:
                focus = "weekday"
                rows = [
                    point
                    for row in sorted(
                        result.get("by_weekday", []),
                        key=lambda row: WEEKDAYS.index(row["weekday"]),
                    )
                    if (point := self._rate_point(row["weekday"], row, minimum=5))
                ]
            elif selected_focus == "comparison" or (
                selected_focus is None and arguments.compare_previous_period
            ):
                focus = "comparison"
                previous = result.get("previous") or {}
                previous_period = previous.get("period") or {}
                if not arguments.compare_previous_period or not previous_period:
                    return None
                previous_start = date.fromisoformat(previous_period["start"])
                previous_end = date.fromisoformat(previous_period["end"])
                if (
                    previous_end + timedelta(days=1) != start
                    or (previous_end - previous_start).days + 1 != arguments.period_days
                ):
                    return None
                rows = [
                    self._rate_point(f"{bounds['start']} – {bounds['end']}", summary, minimum=5)
                    for bounds, summary in (
                        (previous_period, result["previous"]),
                        (period, result["current"]),
                    )
                ]
                if any(point is None for point in rows):
                    return None
                period = {"start": previous_period["start"], "end": period["end"]}
                title, x_axis = "Completion rate by period", "Recorded period"
                note = (
                    "Recorded outcomes in two equal-length periods; at least 5 outcomes per period."
                )
            else:
                focus = "trend"
                rows = self._weekly_points(result)
                chart_type, title, x_axis = "line", "Weekly completion rate", "Week starting Monday"
                interval_days = 7
                note = (
                    "Recorded outcomes by calendar week within the requested dates; boundary weeks "
                    "may be partial. Weeks with fewer than 5 outcomes are uncertain; see counts. "
                    "Absent weeks are gaps, not 0% completion."
                )
        elif tool_name == "get_failure_patterns" and isinstance(arguments, GetFailurePatternsArgs):
            focus = "failure"
            rows = [
                {"label": row["reason"], "value": row["count"], "sample_size": row["count"]}
                for row in result.get("failure_reasons", [])
                if row["count"] > 0
            ]
            units, title, x_axis = "count", "Recorded failure reasons", "Reason"
            note = (
                "Top recorded reasons only; missing reasons are excluded. Correlation is not cause."
            )
        if selected_focus and focus != selected_focus:
            return None
        if len(rows) < 2 or sum(row["sample_size"] for row in rows) < 5:
            return None
        scope = result.get("scope") or {}
        scope_label = scope.get("title_query") or scope.get("category")
        if scope_label:
            title += f" ({scope_label})"
        return CoachChartSpec.model_validate(
            {
                "chart_type": chart_type,
                "title": title,
                "x_axis": x_axis,
                "y_axis": "Completion rate (%)" if units == "percent" else "Recorded failures",
                "units": units,
                "period": {key: period[key] for key in ("start", "end")},
                "data": rows,
                "sample_size": sum(row["sample_size"] for row in rows),
                "note": note,
                "interval_days": interval_days,
                "focus": focus,
            }
        )
