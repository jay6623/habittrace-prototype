"""Period-based patterns learned from a user's recorded outcomes."""

from __future__ import annotations

from collections import defaultdict
from datetime import date, datetime, timedelta
from typing import Any
from uuid import UUID

from ..repositories.personalization_repository import PersonalizationRepository

PERIOD_DAYS = {"week": 7, "month": 30, "3months": 90}
MIN_PATTERN_SUPPORT = 2


class PersonalizedInsightsService:
    def __init__(self, history: PersonalizationRepository) -> None:
        self.history = history

    def get(self, user_id: UUID, period: str, end_date: date) -> dict:
        days = PERIOD_DAYS[period]
        current_start = end_date - timedelta(days=days - 1)
        previous_start = current_start - timedelta(days=days)
        previous_end = current_start - timedelta(days=1)
        rows = self.history.list_completed_tasks(user_id)
        current = self._within(rows, current_start, end_date)
        previous = self._within(rows, previous_start, previous_end)

        if not current:
            return {
                "available": False,
                "reason": "insufficient_data",
                "period": period,
                "sample_count": 0,
                "confidence_label": "learning",
                "success_rate": None,
                "previous_success_rate": self._success_rate(previous),
                "change_percentage_points": None,
                "strongest_pattern": None,
                "pattern_to_watch": None,
                "recommended_experiment": self._default_experiment(),
            }

        success_rate = self._success_rate(current)
        previous_rate = self._success_rate(previous)
        patterns = self._patterns(current, success_rate or 0.0)
        positive = [pattern for pattern in patterns if pattern["difference"] > 0]
        negative = [pattern for pattern in patterns if pattern["difference"] < 0]
        strongest = max(positive, key=self._pattern_rank, default=None)
        watch = min(negative, key=lambda item: item["difference"], default=None)

        return {
            "available": True,
            "reason": None,
            "period": period,
            "sample_count": len(current),
            "confidence_label": self._confidence_label(len(current)),
            "success_rate": success_rate,
            "previous_success_rate": previous_rate,
            "change_percentage_points": (
                round((success_rate or 0.0) - previous_rate, 1)
                if previous_rate is not None
                else None
            ),
            "strongest_pattern": strongest,
            "pattern_to_watch": watch,
            "recommended_experiment": self._experiment(watch, strongest),
        }

    @staticmethod
    def _within(rows: list[dict], start: date, end: date) -> list[dict]:
        result = []
        for row in rows:
            try:
                planned_date = date.fromisoformat(str(row.get("planned_date")))
            except ValueError:
                continue
            if start <= planned_date <= end:
                result.append(row)
        return result

    @staticmethod
    def _success_rate(rows: list[dict]) -> float | None:
        if not rows:
            return None
        successes = sum(row.get("task_status") == "success" for row in rows)
        return round(successes / len(rows) * 100, 1)

    def _patterns(self, rows: list[dict], baseline: float) -> list[dict]:
        groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
        for row in rows:
            values = {
                "category": str(row.get("task_category") or "Other"),
                "time_of_day": self._time_bucket(row.get("planned_start_time")),
                "weekday": date.fromisoformat(str(row["planned_date"])).strftime("%A"),
                "duration": self._duration_bucket(row.get("planned_duration_min")),
            }
            for factor_type, label in values.items():
                groups[(factor_type, label)].append(row)

        patterns = []
        for (factor_type, label), matches in groups.items():
            if len(matches) < MIN_PATTERN_SUPPORT:
                continue
            rate = self._success_rate(matches) or 0.0
            difference = round(rate - baseline, 1)
            if abs(difference) < 5:
                continue
            direction = "positive" if difference > 0 else "negative"
            patterns.append(
                {
                    "type": factor_type,
                    "label": label,
                    "direction": direction,
                    "sample_count": len(matches),
                    "success_rate": rate,
                    "difference": difference,
                    "message": self._message(
                        factor_type, label, direction, len(matches), rate
                    ),
                }
            )
        return patterns

    @staticmethod
    def _pattern_rank(pattern: dict) -> tuple[float, int]:
        return float(pattern["difference"]), int(pattern["sample_count"])

    @staticmethod
    def _confidence_label(sample_count: int) -> str:
        if sample_count < 3:
            return "learning"
        if sample_count < 8:
            return "early"
        if sample_count < 20:
            return "moderate"
        return "strong"

    @staticmethod
    def _duration_bucket(value: object) -> str:
        try:
            minutes = int(str(value or 0))
        except ValueError:
            minutes = 0
        if minutes <= 30:
            return "30 minutes or less"
        if minutes <= 60:
            return "31–60 minutes"
        if minutes <= 120:
            return "61–120 minutes"
        return "more than 2 hours"

    @staticmethod
    def _time_bucket(value: object) -> str:
        raw = str(value or "").strip().upper()
        hour = 12
        for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
            try:
                hour = datetime.strptime(raw, pattern).hour
                break
            except ValueError:
                continue
        if hour < 6:
            return "overnight"
        if hour < 12:
            return "morning"
        if hour < 17:
            return "afternoon"
        if hour < 21:
            return "evening"
        return "night"

    @staticmethod
    def _message(
        factor_type: str, label: str, direction: str, sample_count: int, rate: float
    ) -> str:
        subject = {
            "category": f"{label} plans",
            "time_of_day": f"Plans in the {label}",
            "weekday": f"Plans on {label}",
            "duration": f"Plans lasting {label}",
        }[factor_type]
        tendency = "worked better" if direction == "positive" else "worked less often"
        return f"{subject} {tendency} ({rate:.0f}% across {sample_count} outcomes)."

    @staticmethod
    def _default_experiment() -> dict[str, str]:
        return {
            "title": "Record one clear outcome",
            "detail": "Complete or review each plan so your personal patterns become clearer.",
        }

    def _experiment(self, watch: dict | None, strongest: dict | None) -> dict[str, str]:
        if watch:
            factor_type = watch["type"]
            label = watch["label"]
            suggestions = {
                "duration": (
                    "Try a shorter block",
                    f"For a plan that would last {label}, test a 30–60 minute first block.",
                ),
                "time_of_day": (
                    "Test a different time",
                    f"Move one important plan away from the {label} and record the result.",
                ),
                "weekday": (
                    "Lighten that day",
                    f"Keep one plan smaller on {label} and compare how it goes.",
                ),
                "category": (
                    "Make the first step smaller",
                    f"For your next {label} plan, define one concrete starting action.",
                ),
            }
            title, detail = suggestions[factor_type]
            return {"title": title, "detail": detail}
        if strongest:
            return {
                "title": "Repeat what worked",
                "detail": f"Schedule one meaningful plan under your {strongest['label']} pattern and record the outcome.",
            }
        return self._default_experiment()
