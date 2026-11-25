"""Transparent duration estimates from completed, comparable personal plans."""

import math
from datetime import datetime, timedelta, timezone
from statistics import median
from uuid import UUID

from pydantic import BaseModel

from ..repositories.duration_repository import DurationRepository


class DurationRecommendation(BaseModel):
    available: bool
    recommended_minutes: int | None = None
    sample_count: int = 0
    basis: str = "insufficient_history"
    median_elapsed_minutes: float | None = None
    observed_lower_minutes: int | None = None
    observed_upper_minutes: int | None = None
    range_note: str = (
        "Observed middle 50% of comparable recorded durations: active minutes when reported, "
        "otherwise elapsed time. This is not a confidence interval."
    )
    lookback_days: int = 90
    reason: str | None = None


def _normalized(value: str) -> str:
    return " ".join(value.casefold().split())


def _timestamp(value: str) -> datetime:
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError("Ambiguous timestamp")
    return result


class DurationService:
    def __init__(self, repository: DurationRepository):
        self.repository = repository

    def get(
        self,
        user_id: UUID,
        title: str,
        category: str,
        planned_minutes: int,
        exclude_task_id: UUID | None = None,
        *,
        now: datetime | None = None,
    ) -> DurationRecommendation:
        now = now or datetime.now(timezone.utc)
        since = now - timedelta(days=90)
        exact, comparable = [], []
        seen = set()
        for row in self.repository.list_observations(user_id):
            task_id = row.get("task_id")
            if not task_id or task_id == str(exclude_task_id) or task_id in seen:
                continue
            # Repository returns most recent first. Never count one plan twice.
            seen.add(task_id)
            plan = row.get("plan")
            if not isinstance(plan, dict) or row.get("outcome_status") != "completed":
                continue
            if row.get("task_status") != "success":
                continue
            try:
                captured = _timestamp(plan["captured_at"])
                if row.get("active_minutes") is not None:
                    minutes = float(row["active_minutes"])
                    end = _timestamp(row.get("actual_end_time") or row["created_at"])
                    start = (
                        _timestamp(row["actual_start_time"])
                        if row.get("actual_start_time")
                        else captured
                    )
                else:
                    start, end = (
                        _timestamp(row["actual_start_time"]),
                        _timestamp(row["actual_end_time"]),
                    )
                    minutes = (end - start).total_seconds() / 60
                planned = float(plan["planned_duration_minutes"])
            except (KeyError, TypeError, ValueError, AttributeError, OverflowError):
                continue
            if not (since <= end <= now and captured <= start < end and 1 <= minutes <= 720):
                continue
            if _normalized(str(plan.get("category", ""))) != _normalized(category):
                continue
            if not math.isfinite(planned) or not 5 <= planned <= 480:
                continue
            if (
                _normalized(str(plan.get("title", ""))) == _normalized(title)
                and 0.75 * planned_minutes <= planned <= 1.5 * planned_minutes
            ):
                exact.append(minutes)
            if 0.75 * planned_minutes <= planned <= 1.5 * planned_minutes:
                comparable.append(minutes)
        samples, basis = (
            (exact, "same_title") if len(exact) >= 3 else (comparable, "similar_category")
        )
        required = 3 if basis == "same_title" else 5
        if len(samples) < required:
            return DurationRecommendation(
                available=False,
                sample_count=len(samples),
                reason="Not enough comparable completed plans yet.",
            )
        observed = median(samples)
        # Limit one recommendation to a 50% change, rounded to a five-minute block.
        lower = max(5, math.ceil(planned_minutes * 0.5 / 5) * 5)
        upper = min(480, math.floor(planned_minutes * 1.5 / 5) * 5)
        proposed = max(lower, min(upper, math.floor(observed / 5 + 0.5) * 5))
        return DurationRecommendation(
            available=True,
            recommended_minutes=proposed,
            sample_count=len(samples),
            basis=basis,
            median_elapsed_minutes=round(observed, 1),
            observed_lower_minutes=max(1, round(sorted(samples)[int((len(samples) - 1) * 0.25)])),
            observed_upper_minutes=max(
                1, round(sorted(samples)[math.ceil((len(samples) - 1) * 0.75)])
            ),
        )
