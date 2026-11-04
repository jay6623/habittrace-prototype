"""Private, read-only group previews and explicit personal-plan confirmation."""

from __future__ import annotations

import logging
from datetime import datetime, time, timedelta, timezone
from typing import Any
from uuid import UUID

from postgrest.exceptions import APIError

from ..core.errors import (
    DatabaseUnavailableError,
    DomainValidationError,
    RepositoryError,
    ResourceConflictError,
)
from ..schemas.group import GroupPersonalPlanRequest
from ..utils.timezone import get_timezone
from .ai_explanation import build_plan_explanation
from .group_service import GroupService
from .task_service import TaskService

logger = logging.getLogger(__name__)
UTC = timezone.utc


class GroupPersonalPlanningService:
    def __init__(
        self,
        groups: GroupService,
        tasks: TaskService,
        model: Any,
        personalization: Any,
        calendar: Any,
    ) -> None:
        self.groups = groups
        self.tasks = tasks
        self.db = tasks.db
        self.model = model
        self.personalization = personalization
        self.calendar = calendar

    def _assigned_task(self, user_id: UUID, group_id: UUID, task_id: UUID) -> dict:
        return self.groups.get_task_for_assignee(user_id, group_id, task_id)

    def _linked_task(self, user_id: UUID, task_id: UUID) -> dict | None:
        rows = (
            self.db.table("tasks")
            .select("*")
            .eq("user_id", str(user_id))
            .eq("source_group_task_id", str(task_id))
            .limit(1)
            .execute()
        ).data
        if not rows:
            return None
        if not isinstance(rows[0], dict):
            raise RepositoryError()
        return rows[0]

    @staticmethod
    def _deadline(task: dict, timezone_name: str) -> datetime | None:
        if not task.get("due_date"):
            return None
        clock = time.fromisoformat(task["due_time"]) if task.get("due_time") else time(23, 59, 59)
        return datetime.combine(
            datetime.fromisoformat(task["due_date"]).date(),
            clock,
            get_timezone(task.get("due_timezone_name") or timezone_name),
        ).astimezone(UTC)

    def _validate_window(self, task: dict, body: GroupPersonalPlanRequest) -> None:
        start = body.planned_start.astimezone(UTC)
        if start <= datetime.now(UTC):
            raise DomainValidationError("Choose a future start time.")
        deadline = self._deadline(task, body.timezone_name)
        if deadline and start + timedelta(minutes=body.planned_duration_minutes) > deadline:
            raise DomainValidationError("The work block must finish by the group deadline.")

    def _blocks(self, user_id: UUID, body: GroupPersonalPlanRequest) -> tuple[list, list[str]]:
        blocks = []
        warnings = []
        for task in self.tasks.list_for_user(str(user_id)):
            if task.get("task_status") == "failed":
                continue
            start = None
            for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
                try:
                    clock = datetime.strptime(task["planned_start_time"].upper(), pattern).time()
                    start = datetime.combine(
                        datetime.fromisoformat(task["planned_date"]).date(),
                        clock,
                        get_timezone(task.get("timezone_name") or body.timezone_name),
                    ).astimezone(UTC)
                    break
                except ValueError:
                    continue
            if start is None:
                warnings.append("An existing plan has an unreadable time; review your calendar.")
                continue
            blocks.append(
                (
                    start,
                    start + timedelta(minutes=task["planned_duration_min"]),
                    str(task.get("title") or "Existing plan"),
                )
            )
        tz = get_timezone(body.timezone_name)
        day = body.planned_start.astimezone(tz).date()
        day_start = datetime.combine(day, time.min, tz)
        day_end = datetime.combine(day + timedelta(days=1), time.min, tz)
        day_end = max(
            day_end,
            body.planned_start.astimezone(UTC)
            + timedelta(minutes=body.planned_duration_minutes),
        )
        try:
            for event in self.calendar.list_busy_events(str(user_id), day_start, day_end):
                blocks.append(
                    (
                        datetime.fromisoformat(event["start"].replace("Z", "+00:00")),
                        datetime.fromisoformat(event["end"].replace("Z", "+00:00")),
                        str(event.get("title") or "Calendar event"),
                    )
                )
        except Exception:
            logger.warning("Group personal preview could not load calendar events")
            warnings.append("Google Calendar could not be checked; review it before confirming.")
        return blocks, warnings

    @staticmethod
    def _conflicts(start: datetime, duration: int, blocks: list) -> list[str]:
        end = start.astimezone(UTC) + timedelta(minutes=duration)
        return sorted({title for a, b, title in blocks if a < end and b > start})

    def _plan(self, task: dict, body: GroupPersonalPlanRequest, blocks: list) -> dict:
        start = body.planned_start.astimezone(UTC)
        tz = get_timezone(body.timezone_name)
        day = start.astimezone(tz).date()
        daily = [(a, b) for a, b, _ in blocks if a.astimezone(tz).date() == day]
        before = [(a, b) for a, b in daily if a < start]
        previous = max((b for _, b in before), default=None)
        deadline = self._deadline(task, body.timezone_name)
        return {
            "id": "group-personal-preview",
            "input_source": "user",
            "title": task["title"],
            "category": task["category"],
            "planned_start": start.isoformat(),
            "planned_duration_minutes": body.planned_duration_minutes,
            "deadline_at": deadline.isoformat() if deadline else None,
            "importance": {"high": 5, "medium": 3, "low": 2}[task["priority"]],
            "difficulty": 3,
            "required_energy": body.required_energy,
            "required_focus": body.required_focus,
            "current_energy": body.current_energy,
            "current_focus": body.current_focus,
            "sleep_hours": None,
            "stress_level": None,
            "tasks_before_count": len(before),
            "planned_minutes_before": sum(int((b - a).total_seconds() / 60) for a, b in before),
            "daily_planned_minutes": body.planned_duration_minutes
            + sum(int((b - a).total_seconds() / 60) for a, b in daily),
            "minutes_since_previous": max(0, int((start - previous).total_seconds() / 60))
            if previous
            else None,
            "timezone_name": body.timezone_name,
            "is_fixed_time": False,
            "created_at": datetime.now(UTC).isoformat(),
        }

    def _score(
        self,
        task: dict,
        body: GroupPersonalPlanRequest,
        blocks: list,
        profile: Any,
    ) -> dict:
        plan = self._plan(task, body, blocks)
        result = self.personalization.apply(self.model.predict(plan), plan, profile)
        result["explanation"] = {
            **result.get("explanation", {}),
            **build_plan_explanation(plan, result),
        }
        result["recommended_actions"] = result["explanation"]["recommended_actions"]
        return result

    def preview(
        self, user_id: UUID, group_id: UUID, task_id: UUID, body: GroupPersonalPlanRequest
    ) -> dict:
        task = self._assigned_task(user_id, group_id, task_id)
        linked = self._linked_task(user_id, task_id)
        if linked:
            return {"personal_task": linked}
        self._validate_window(task, body)
        blocks, warnings = self._blocks(user_id, body)
        result: dict = {
            "conflicts": self._conflicts(body.planned_start, body.planned_duration_minutes, blocks),
            "warnings": warnings,
            "candidates": [],
        }
        if not self.model.is_ready:
            warnings.append("Prediction is unavailable. You can still add your personal plan.")
            return result
        try:
            profile = self.personalization.build_profile(user_id)
            result["prediction"] = self._score(task, body, blocks, profile)
            tz = get_timezone(body.timezone_name)
            day = body.planned_start.astimezone(tz).date()
            # Search this local day's daytime hours only; every slot is re-scored.
            candidates = []
            for minute in range(8 * 60, 22 * 60, 30):
                start = datetime.combine(day, time(minute // 60, minute % 60), tz).astimezone(UTC)
                if start == body.planned_start or start <= datetime.now(UTC):
                    continue
                candidate = body.model_copy(update={"planned_start": start})
                deadline = self._deadline(task, body.timezone_name)
                end = start + timedelta(minutes=body.planned_duration_minutes)
                if end > datetime.combine(day, time(22), tz).astimezone(UTC):
                    continue
                if deadline and end > deadline:
                    continue
                if self._conflicts(start, body.planned_duration_minutes, blocks):
                    continue
                score = self._score(task, candidate, blocks, profile)
                candidates.append(
                    {
                        "planned_start": start.isoformat(),
                        "success_probability": score["success_probability"],
                    }
                )
            result["candidates"] = sorted(
                candidates, key=lambda c: (-c["success_probability"], c["planned_start"])
            )[:3]
        except (ValueError, TypeError, RuntimeError, RepositoryError, DatabaseUnavailableError):
            logger.warning("Group personal prediction unavailable", exc_info=True)
            warnings.append("Prediction is unavailable. You can still add your personal plan.")
        return result

    def confirm(
        self, user_id: UUID, group_id: UUID, task_id: UUID, body: GroupPersonalPlanRequest
    ) -> dict:
        task = self._assigned_task(user_id, group_id, task_id)
        linked = self._linked_task(user_id, task_id)
        if linked:
            return linked
        self._validate_window(task, body)
        blocks, _warnings = self._blocks(user_id, body)
        if self._conflicts(body.planned_start, body.planned_duration_minutes, blocks):
            linked = self._linked_task(user_id, task_id)
            if linked:
                return linked
            raise ResourceConflictError("This time overlaps another plan. Choose another time.")
        plan = self._plan(task, body, blocks)
        local_start = body.planned_start.astimezone(get_timezone(body.timezone_name))
        payload = {
            "source_group_task_id": str(task_id),
            "title": task["title"],
            "task_category": task["category"],
            "planned_date": local_start.date().isoformat(),
            "planned_start_time": local_start.strftime("%H:%M"),
            "planned_duration_min": body.planned_duration_minutes,
            "importance": plan["importance"],
            "energy_level": body.required_energy,
            "focus_level": body.required_focus,
            "total_tasks_today": 1
            + sum(
                a.astimezone(get_timezone(body.timezone_name)).date() == local_start.date()
                for a, _b, _title in blocks
            ),
            "timezone_name": body.timezone_name,
            "ai_plan_details": {
                "deadline_at": plan["deadline_at"],
                "current_energy": body.current_energy,
                "current_focus": body.current_focus,
            },
        }
        try:
            created = self.tasks.create(str(user_id), payload)
        except APIError as exc:
            if exc.code != "23505":
                raise
            linked = self._linked_task(user_id, task_id)
            if linked is None:
                raise
            return linked
        self.calendar.sync_task_safely(str(user_id), created)
        return created
