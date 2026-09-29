"""Adapter from AI Coach batch requests to the daily schedule generator."""

from __future__ import annotations

from datetime import date, datetime, time
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ..schemas.coach_tools import GenerateDailyScheduleArgs
from ..schemas.daily_schedule import DailyScheduleGenerate
from .coaching_context_service import CoachingContextService
from .daily_schedule_service import DailyScheduleService


class CoachingDailyScheduleService:
    def __init__(
        self,
        context_service: CoachingContextService,
        schedule_service: DailyScheduleService,
    ) -> None:
        self.context_service = context_service
        self.schedule_service = schedule_service

    def generate(
        self,
        user_id: str,
        arguments: GenerateDailyScheduleArgs,
        *,
        timezone_name: str,
    ) -> dict:
        try:
            zone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            zone = ZoneInfo("UTC")
            timezone_name = "UTC"

        selected_date = arguments.selected_date or datetime.now(zone).date()
        preferences = self.context_service.get_preferences(user_id, timezone_name)
        day_start = self._clock(preferences.get("preferred_day_start"), time(8, 0))
        day_end = self._clock(preferences.get("preferred_day_end"), time(22, 0))
        minimum_buffer = int(preferences.get("minimum_buffer_minutes") or 0)

        tasks = []
        for task in arguments.tasks:
            deadline = self._aware_datetime(selected_date, task.deadline_time, zone)
            fixed_start = self._aware_datetime(selected_date, task.fixed_start_time, zone)
            tasks.append(
                {
                    "title": task.title,
                    "estimated_duration_minutes": task.estimated_duration_minutes,
                    "deadline_at": deadline,
                    "importance": task.importance,
                    "category": task.category,
                    "difficulty": task.difficulty,
                    "required_energy": task.required_energy,
                    "required_focus": task.required_focus,
                    "is_fixed_time": fixed_start is not None,
                    "fixed_start": fixed_start,
                }
            )

        draft = self.schedule_service.generate(
            UUID(user_id),
            DailyScheduleGenerate(
                selected_date=selected_date,
                timezone_name=timezone_name,
                day_start=day_start,
                day_end=day_end,
                minimum_buffer_minutes=minimum_buffer,
                tasks=tasks,
            ),
        )
        return draft

    @staticmethod
    def _clock(value: object, fallback: time) -> time:
        try:
            return time.fromisoformat(str(value))
        except (TypeError, ValueError):
            return fallback

    @staticmethod
    def _aware_datetime(
        selected_date: date,
        clock: str | None,
        zone: ZoneInfo,
    ) -> datetime | None:
        if clock is None:
            return None
        return datetime.combine(selected_date, time.fromisoformat(clock), tzinfo=zone)
