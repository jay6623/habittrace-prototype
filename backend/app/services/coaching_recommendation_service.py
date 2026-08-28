"""Deterministic, explainable schedule recommendations for chat proposals."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .analytics_service import _hour_from_time_str


def _parse_clock(value: str | None, fallback: str) -> time:
    raw = (value or fallback).strip().upper()
    for fmt in ("%H:%M", "%H:%M:%S", "%I:%M %p", "%I:%M%p", "%I %p", "%I%p"):
        try:
            return datetime.strptime(raw, fmt).time()
        except ValueError:
            continue
    return datetime.strptime(fallback, "%H:%M").time()


def _clock_string(value: object) -> str:
    raw = str(value or "12:00")
    return f"{_hour_from_time_str(raw):02d}:{raw.split(':')[1][:2] if ':' in raw else '00'}"


class CoachingRecommendationService:
    def recommend(
        self,
        plan: dict[str, Any],
        context: dict[str, Any],
    ) -> list[dict[str, Any]]:
        target_date = date.fromisoformat(str(plan["planned_date"]))
        duration = int(plan.get("duration_minutes") or 60)
        preferences = context.get("preferences") or {}
        try:
            user_timezone = ZoneInfo(str(preferences.get("timezone_name") or "UTC"))
        except ZoneInfoNotFoundError:
            user_timezone = ZoneInfo("UTC")
        exact = plan.get("exact_time")
        day_start = _parse_clock(
            exact or plan.get("earliest_time"),
            str(preferences.get("preferred_day_start") or "08:00"),
        )
        day_end = _parse_clock(
            exact or plan.get("latest_time"),
            str(preferences.get("preferred_day_end") or "22:00"),
        )
        minimum_buffer = int(preferences.get("minimum_buffer_minutes") or 0)

        start = datetime.combine(target_date, day_start)
        if exact:
            latest_start = start
        else:
            latest_end = datetime.combine(target_date, day_end)
            latest_start = latest_end - timedelta(minutes=duration)
        if latest_start < start:
            return []

        schedule: list[tuple[datetime, datetime]] = []
        daily_minutes = 0
        for item in context.get("upcoming_schedule") or []:
            if str(item.get("date")) != target_date.isoformat():
                continue
            item_start = datetime.combine(
                target_date,
                _parse_clock(_clock_string(item.get("time")), "12:00"),
            )
            item_duration = int(item.get("duration_minutes") or 0)
            schedule.append((item_start, item_start + timedelta(minutes=item_duration)))
            daily_minutes += item_duration

        overall = (context.get("last_30_days") or {}).get("success_rate")
        baseline = float(overall) / 100 if overall is not None else 0.55
        hour_lookup = {
            int(row["hour"]): row
            for row in context.get("hour_patterns") or []
            if row.get("success_rate") is not None
        }
        category_lookup = {
            str(row["category"]).lower(): row
            for row in context.get("category_patterns") or []
            if row.get("success_rate") is not None
        }
        category = str(plan.get("category") or "Other")

        options: list[dict[str, Any]] = []
        current = start
        while current <= latest_start:
            end = current + timedelta(minutes=duration)
            buffer = timedelta(minutes=minimum_buffer)
            if any(
                current < busy_end + buffer and end + buffer > busy_start
                for busy_start, busy_end in schedule
            ):
                current += timedelta(minutes=30)
                continue

            score = baseline
            reasons = ["It does not conflict with your existing schedule."]
            hour_pattern = hour_lookup.get(current.hour)
            if hour_pattern and int(hour_pattern.get("sample_size") or 0) >= 3:
                hour_rate = float(hour_pattern["success_rate"]) / 100
                score = score * 0.55 + hour_rate * 0.45
                reasons.append(
                    f"Your recorded success rate around {current.strftime('%-I %p')} is "
                    f"{hour_pattern['success_rate']}% across {hour_pattern['sample_size']} tasks."
                )
            category_pattern = category_lookup.get(category.lower())
            if category_pattern and int(category_pattern.get("sample_size") or 0) >= 3:
                category_rate = float(category_pattern["success_rate"]) / 100
                score = score * 0.75 + category_rate * 0.25
                reasons.append(
                    f"Your {category} task success rate is {category_pattern['success_rate']}%."
                )
            projected_minutes = daily_minutes + duration
            if projected_minutes > 480:
                score -= min(0.2, (projected_minutes - 480) / 1200)
                reasons.append(
                    "This is a relatively full day, so the score includes a workload penalty."
                )
            if not hour_pattern or int(hour_pattern.get("sample_size") or 0) < 3:
                reasons.append(
                    "There is limited history for this exact hour, so this estimate has "
                    "lower confidence."
                )

            options.append(
                {
                    "start": current.replace(tzinfo=user_timezone).isoformat(),
                    "end": end.replace(tzinfo=user_timezone).isoformat(),
                    "score": round(max(0.05, min(0.95, score)), 3),
                    "reasons": reasons,
                }
            )
            current += timedelta(minutes=30)

        options.sort(key=lambda item: (-item["score"], item["start"]))
        return options[:3]
