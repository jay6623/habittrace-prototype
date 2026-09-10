"""Read-only AI V2 summary for the user's current plans."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from .ai_explanation import build_plan_explanation
from .ai_v2_ml_service import AIV2MLService
from .personalization_service import PersonalizationService


class PersonalizedOutlookService:
    def __init__(
        self,
        db: Any,
        model: AIV2MLService,
        personalization: PersonalizationService,
    ) -> None:
        self.db = db
        self.model = model
        self.personalization = personalization

    def get(self, user_id: UUID, planned_date: date, timezone_name: str) -> dict:
        timezone = ZoneInfo(timezone_name)
        tasks = list(
            (
                self.db.table("tasks")
                .select("*")
                .eq("user_id", str(user_id))
                .eq("planned_date", planned_date.isoformat())
                .eq("task_status", "pending")
                .execute()
            ).data
            or []
        )
        if not tasks:
            return self._empty("no_pending_plans")
        if not self.model.is_ready:
            return self._empty("model_unavailable", task_count=len(tasks))

        profile = self.personalization.build_profile(user_id)
        ordered = sorted(tasks, key=lambda task: self._minutes(task.get("planned_start_time")))
        daily_minutes = sum(int(task.get("planned_duration_min") or 0) for task in ordered)
        scored: list[dict] = []
        elapsed_minutes = 0
        previous_end: datetime | None = None

        for index, task in enumerate(ordered):
            start = self._planned_start(
                planned_date,
                str(task.get("planned_start_time") or "12:00 PM"),
                timezone,
            )
            duration = max(1, int(task.get("planned_duration_min") or 60))
            plan = {
                "id": task.get("id"),
                "input_source": "user",
                "title": task.get("title") or "Untitled plan",
                "category": task.get("task_category") or "Other",
                "planned_start": start.isoformat(),
                "planned_duration_minutes": duration,
                "deadline_at": None,
                "importance": int(task.get("importance") or 3),
                "difficulty": 3,
                "required_energy": int(task.get("energy_level") or 3),
                "required_focus": int(task.get("focus_level") or 3),
                "current_energy": int(task.get("energy_level") or 3),
                "current_focus": int(task.get("focus_level") or 3),
                "sleep_hours": None,
                "stress_level": None,
                "tasks_before_count": index,
                "planned_minutes_before": elapsed_minutes,
                "daily_planned_minutes": daily_minutes,
                "minutes_since_previous": (
                    max(0, round((start - previous_end).total_seconds() / 60))
                    if previous_end is not None
                    else None
                ),
                "timezone_name": timezone_name,
                "is_fixed_time": True,
                "created_at": datetime.now(timezone).isoformat(),
            }
            base = self.model.predict(plan)
            result = self.personalization.apply(base, plan, profile)
            explanation = build_plan_explanation(plan, result)
            scored.append(
                {
                    "id": str(task.get("id") or ""),
                    "title": plan["title"],
                    "success_probability": float(result["success_probability"]),
                    "predicted_failure_reason": result.get("predicted_failure_reason"),
                    "personalization": result["personalization"],
                    "recommended_actions": explanation["recommended_actions"],
                }
            )
            elapsed_minutes += duration
            previous_end = start + timedelta(minutes=duration)

        highest = max(scored, key=lambda item: item["success_probability"])
        attention = min(scored, key=lambda item: item["success_probability"])
        factors = self._unique_factors(scored)
        recommendation = (attention["recommended_actions"] or [None])[0]
        confidence = profile.sample_count / (profile.sample_count + 20.0)
        history_rate = scored[0]["personalization"].get("history_success_rate")
        return {
            "available": True,
            "reason": None,
            "date": planned_date.isoformat(),
            "task_count": len(scored),
            "predicted_success_probability": sum(
                item["success_probability"] for item in scored
            )
            / len(scored),
            "highest_potential": highest,
            "needs_attention": attention,
            "recommendation": recommendation,
            "personalization": {
                "applied": bool(profile.examples),
                "sample_count": profile.sample_count,
                "confidence": confidence,
                "history_success_rate": history_rate,
                "factors": factors[:3],
            },
        }

    @staticmethod
    def _empty(reason: str, task_count: int = 0) -> dict:
        return {
            "available": False,
            "reason": reason,
            "date": None,
            "task_count": task_count,
            "predicted_success_probability": None,
            "highest_potential": None,
            "needs_attention": None,
            "recommendation": None,
            "personalization": {
                "applied": False,
                "sample_count": 0,
                "confidence": 0.0,
                "history_success_rate": None,
                "factors": [],
            },
        }

    @staticmethod
    def _minutes(value: object) -> int:
        raw = str(value or "").strip().upper()
        for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
            try:
                parsed = datetime.strptime(raw, pattern)
                return parsed.hour * 60 + parsed.minute
            except ValueError:
                continue
        return 12 * 60

    @classmethod
    def _planned_start(
        cls, planned_date: date, value: str, timezone: ZoneInfo
    ) -> datetime:
        minutes = cls._minutes(value)
        return datetime(
            planned_date.year,
            planned_date.month,
            planned_date.day,
            minutes // 60,
            minutes % 60,
            tzinfo=timezone,
        )

    @staticmethod
    def _unique_factors(scored: list[dict]) -> list[dict]:
        factors: dict[tuple[str, str], dict] = {}
        for item in scored:
            for factor in item["personalization"].get("factors", []):
                key = (str(factor.get("type")), str(factor.get("direction")))
                current = factors.get(key)
                if current is None or int(factor.get("sample_count", 0)) > int(
                    current.get("sample_count", 0)
                ):
                    factors[key] = factor
        return sorted(
            factors.values(),
            key=lambda factor: int(factor.get("sample_count", 0)),
            reverse=True,
        )
