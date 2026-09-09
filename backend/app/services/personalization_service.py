"""History-based probability adjustment layered over the shared plan model."""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from ..repositories.personalization_repository import PersonalizationRepository

UTC = timezone.utc
MIN_FACTOR_SUPPORT = 2
PRIOR_STRENGTH = 8.0
PERSONALIZATION_STRENGTH = 20.0
MAX_HISTORY_ROWS = 200


def _datetime(value: object) -> datetime:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("personalization timestamps must include a timezone")
    return parsed.astimezone(UTC)


def _duration_bucket(minutes: object) -> str:
    try:
        value = int(str(minutes or 0))
    except (TypeError, ValueError):
        value = 0
    if value <= 30:
        return "short"
    if value <= 60:
        return "medium"
    if value <= 120:
        return "long"
    return "extended"


def _local_datetime(value: object, timezone_name: object) -> datetime:
    name = str(timezone_name or "UTC")
    return _datetime(value).astimezone(ZoneInfo(name))


def _time_bucket(value: object, timezone_name: object) -> str:
    hour = _local_datetime(value, timezone_name).hour
    if hour < 6:
        return "overnight"
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    if hour < 21:
        return "evening"
    return "night"


def _stored_time_bucket(value: object) -> str:
    raw = str(value or "").strip().upper()
    for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
        try:
            hour = datetime.strptime(raw, pattern).hour
            if hour < 6:
                return "overnight"
            if hour < 12:
                return "morning"
            if hour < 17:
                return "afternoon"
            if hour < 21:
                return "evening"
            return "night"
        except ValueError:
            continue
    return "unknown"


@dataclass(frozen=True)
class HistoryExample:
    category: str
    time_bucket: str
    weekday: int
    duration_bucket: str
    success: float
    weight: float


@dataclass(frozen=True)
class PersonalizationProfile:
    examples: tuple[HistoryExample, ...]

    @property
    def sample_count(self) -> int:
        return len(self.examples)


class PersonalizationService:
    """Adjust shared-model output using only the authenticated user's outcomes."""

    def __init__(self, history: PersonalizationRepository) -> None:
        self.history = history

    def build_profile(
        self,
        user_id: UUID,
        *,
        exclude_plan_id: object | None = None,
        as_of: datetime | None = None,
    ) -> PersonalizationProfile:
        cutoff = (as_of or datetime.now(UTC)).astimezone(UTC)
        rows = self.history.list_completed_tasks(user_id)
        examples: list[HistoryExample] = []
        for row in rows:
            if exclude_plan_id is not None and str(row.get("id")) == str(exclude_plan_id):
                continue
            planned_date_value = row.get("planned_date")
            if not planned_date_value:
                continue
            planned_date = datetime.fromisoformat(str(planned_date_value)).date()
            history_date = datetime.combine(
                planned_date,
                datetime.min.time(),
                tzinfo=UTC,
            )
            if history_date > cutoff:
                continue
            age_days = max(0.0, (cutoff - history_date).total_seconds() / 86_400)
            recency_weight = math.pow(0.5, age_days / 90.0)
            success = float(row.get("task_status") == "success")
            examples.append(
                HistoryExample(
                    category=str(row.get("task_category") or "").strip().lower(),
                    time_bucket=_stored_time_bucket(row.get("planned_start_time")),
                    weekday=planned_date.weekday(),
                    duration_bucket=_duration_bucket(row.get("planned_duration_min")),
                    success=success,
                    weight=recency_weight,
                )
            )
            if len(examples) >= MAX_HISTORY_ROWS:
                break
        return PersonalizationProfile(tuple(examples))

    def apply(
        self,
        base_result: dict[str, Any],
        plan: dict[str, Any],
        profile: PersonalizationProfile,
    ) -> dict[str, Any]:
        base_probability = float(base_result["success_probability"])
        if not profile.examples:
            return {
                **base_result,
                "base_success_probability": base_probability,
                "personalization": {
                    "applied": False,
                    "sample_count": 0,
                    "confidence": 0.0,
                    "history_success_rate": None,
                    "factors": [],
                },
            }

        overall_rate = self._weighted_rate(profile.examples)
        signals: list[tuple[str, str, list[HistoryExample]]] = [
            (
                "category",
                str(plan.get("category") or "").strip().lower(),
                [
                    example
                    for example in profile.examples
                    if example.category == str(plan.get("category") or "").strip().lower()
                ],
            ),
            (
                "time_of_day",
                _time_bucket(plan.get("planned_start"), plan.get("timezone_name")),
                [
                    example
                    for example in profile.examples
                    if example.time_bucket
                    == _time_bucket(plan.get("planned_start"), plan.get("timezone_name"))
                ],
            ),
            (
                "weekday",
                str(
                    _local_datetime(
                        plan.get("planned_start"), plan.get("timezone_name")
                    ).weekday()
                ),
                [
                    example
                    for example in profile.examples
                    if example.weekday
                    == _local_datetime(
                        plan.get("planned_start"), plan.get("timezone_name")
                    ).weekday()
                ],
            ),
            (
                "duration",
                _duration_bucket(plan.get("planned_duration_minutes")),
                [
                    example
                    for example in profile.examples
                    if example.duration_bucket
                    == _duration_bucket(plan.get("planned_duration_minutes"))
                ],
            ),
        ]

        estimates: list[tuple[float, float]] = [(overall_rate, 1.0)]
        factors: list[dict[str, Any]] = []
        for factor_type, label, matches in signals:
            if not matches:
                continue
            support_weight = sum(example.weight for example in matches)
            successes = sum(example.success * example.weight for example in matches)
            rate = (successes + base_probability * PRIOR_STRENGTH) / (
                support_weight + PRIOR_STRENGTH
            )
            estimates.append((rate, min(2.0, support_weight / 3.0)))
            if len(matches) >= MIN_FACTOR_SUPPORT:
                difference = rate - base_probability
                if abs(difference) >= 0.02:
                    direction = "positive" if difference > 0 else "negative"
                    factors.append(
                        {
                            "type": factor_type,
                            "direction": direction,
                            "sample_count": len(matches),
                            "message": self._factor_message(
                                factor_type, label, direction, len(matches)
                            ),
                        }
                    )

        personal_score = sum(score * weight for score, weight in estimates) / sum(
            weight for _score, weight in estimates
        )
        confidence = profile.sample_count / (
            profile.sample_count + PERSONALIZATION_STRENGTH
        )
        final_probability = max(
            0.0,
            min(1.0, base_probability * (1.0 - confidence) + personal_score * confidence),
        )
        factors.sort(
            key=lambda factor: factor["sample_count"],
            reverse=True,
        )
        return {
            **base_result,
            "success_probability": final_probability,
            "base_success_probability": base_probability,
            "personalization": {
                "applied": True,
                "sample_count": profile.sample_count,
                "confidence": confidence,
                "history_success_rate": overall_rate,
                "factors": factors[:3],
            },
        }

    @staticmethod
    def _weighted_rate(examples: list[HistoryExample] | tuple[HistoryExample, ...]) -> float:
        total_weight = sum(example.weight for example in examples)
        if total_weight <= 0:
            return 0.0
        return sum(example.success * example.weight for example in examples) / total_weight

    @staticmethod
    def _factor_message(
        factor_type: str, label: str, direction: str, sample_count: int
    ) -> str:
        tendency = "more often" if direction == "positive" else "less often"
        descriptions: dict[str, Callable[[], str]] = {
            "category": lambda: f"You complete {label or 'similar'} plans {tendency}.",
            "time_of_day": lambda: f"You complete plans {tendency} in the {label}.",
            "weekday": lambda: f"Your record for this weekday is {tendency} successful.",
            "duration": lambda: f"You complete plans of this length {tendency}.",
        }
        message = descriptions[factor_type]()
        return f"{message} Based on {sample_count} previous plans."
