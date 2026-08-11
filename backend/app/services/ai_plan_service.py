"""Business rules for immutable AI plan inputs."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from ..core.errors import (
    DomainValidationError,
    RepositoryError,
    ResourceConflictError,
    ResourceNotFoundError,
)
from ..repositories.ai_plan_repository import AIPlanRepository
from ..schemas.ai_plan import PlanInputCreate, PlanInputSource, plan_input_to_insert
from ..utils.timezone import as_local


@dataclass(frozen=True)
class ScheduleContext:
    tasks_before_count: int
    planned_minutes_before: int
    daily_planned_minutes: int
    minutes_since_previous: int | None


def _parse_database_datetime(value: object) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError) as exc:
        raise RepositoryError("The database returned an invalid plan timestamp.") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise RepositoryError("The database returned an invalid plan timestamp.")
    return parsed


class AIPlanService:
    def __init__(self, plans: AIPlanRepository) -> None:
        self.plans = plans

    def create(self, user_id: UUID, body: PlanInputCreate) -> dict:
        parent_id = body.parent_plan_input_id
        if parent_id is not None:
            if self.plans.get_owned(parent_id, user_id) is None:
                raise ResourceNotFoundError("Parent plan not found.")
            if self.plans.has_child(parent_id):
                raise ResourceConflictError("The parent plan has already been revised.")
            if body.input_source is PlanInputSource.USER:
                raise DomainValidationError(
                    "A revised plan must use input_source 'reschedule'."
                )
        elif body.input_source is not PlanInputSource.USER:
            raise DomainValidationError(
                "A rescheduled plan must reference a parent plan."
            )

        context = self._calculate_schedule_context(user_id, body)
        payload = plan_input_to_insert(
            body,
            user_id=user_id,
            tasks_before_count=context.tasks_before_count,
            planned_minutes_before=context.planned_minutes_before,
            daily_planned_minutes=context.daily_planned_minutes,
            minutes_since_previous=context.minutes_since_previous,
        )
        return self.plans.create(payload)

    def get(self, user_id: UUID, plan_input_id: UUID) -> dict:
        plan = self.plans.get_owned(plan_input_id, user_id)
        if plan is None:
            raise ResourceNotFoundError("Plan not found.")
        return plan

    def _calculate_schedule_context(
        self, user_id: UUID, body: PlanInputCreate
    ) -> ScheduleContext:
        rows = self.plans.list_schedule_rows(user_id)
        superseded_ids = {
            str(row["parent_plan_input_id"])
            for row in rows
            if row.get("parent_plan_input_id")
        }
        if body.parent_plan_input_id is not None:
            superseded_ids.add(str(body.parent_plan_input_id))

        target_local = as_local(body.planned_start, body.timezone_name)
        same_day: list[tuple[datetime, int]] = []
        for row in rows:
            if str(row.get("id")) in superseded_ids:
                continue
            start = _parse_database_datetime(row.get("planned_start"))
            if as_local(start, body.timezone_name).date() != target_local.date():
                continue
            try:
                duration = int(row.get("planned_duration_minutes", 0))
            except (TypeError, ValueError) as exc:
                raise RepositoryError(
                    "The database returned an invalid plan duration."
                ) from exc
            same_day.append((start, duration))

        before = [item for item in same_day if item[0] < body.planned_start]
        tasks_before_count = len(before)
        planned_minutes_before = sum(duration for _start, duration in before)
        daily_planned_minutes = (
            sum(duration for _start, duration in same_day)
            + body.planned_duration_minutes
        )

        minutes_since_previous: int | None = None
        if before:
            previous_start, previous_duration = max(before, key=lambda item: item[0])
            previous_end = previous_start + timedelta(minutes=previous_duration)
            gap = int((body.planned_start - previous_end).total_seconds() // 60)
            minutes_since_previous = max(0, gap)

        return ScheduleContext(
            tasks_before_count=tasks_before_count,
            planned_minutes_before=planned_minutes_before,
            daily_planned_minutes=daily_planned_minutes,
            minutes_since_previous=minutes_since_previous,
        )
