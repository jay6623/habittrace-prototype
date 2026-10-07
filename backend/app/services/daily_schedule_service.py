"""Explainable MVP optimizer for draft-first daily schedules."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from uuid import UUID

from ..core.errors import DomainValidationError, ResourceConflictError, ResourceNotFoundError
from ..repositories.ai_plan_repository import AIPlanRepository
from ..repositories.daily_schedule_repository import DailyScheduleRepository
from ..schemas.daily_schedule import (
    DailyScheduleGenerate,
    DailyScheduleTaskInput,
    DailyScheduleUpdate,
)
from ..utils.timezone import as_local, get_timezone
from .ai_v2_ml_service import AIV2MLService
from .google_calendar_service import GoogleCalendarService
from .personalization_service import PersonalizationService
from .task_service import TaskService


@dataclass(frozen=True)
class ScheduleBlock:
    start: datetime
    end: datetime
    title: str
    required_focus: int = 3
    source: str = "existing"


def _parse_datetime(value: object) -> datetime:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise DomainValidationError("Schedule timestamps must include a UTC offset.")
    return parsed


class DailyScheduleService:
    """Greedy optimizer behind an interface that can later host a global solver."""

    def __init__(
        self,
        plans: AIPlanRepository,
        drafts: DailyScheduleRepository,
        tasks: TaskService,
        model_service: AIV2MLService,
        personalization: PersonalizationService,
        calendar: GoogleCalendarService | None = None,
    ) -> None:
        self.plans = plans
        self.drafts = drafts
        self.tasks = tasks
        self.model_service = model_service
        self.personalization = personalization
        self.calendar = calendar

    def generate(self, user_id: UUID, body: DailyScheduleGenerate) -> dict:
        if not self.model_service.is_ready:
            raise RuntimeError("AI V2 model artifacts are not loaded")

        day_start, day_end = self._day_bounds(body)
        existing, warnings = self._existing_blocks(user_id, body, day_start, day_end)
        profile = self.personalization.build_profile(user_id)
        scheduled: list[dict[str, Any]] = []
        unscheduled: list[dict[str, Any]] = []
        generated_blocks: list[ScheduleBlock] = []
        existing_minutes = self._covered_minutes(existing, day_start, day_end)

        fixed = [task for task in body.tasks if task.is_fixed_time]
        flexible = sorted(
            (task for task in body.tasks if not task.is_fixed_time),
            key=self._priority_key,
        )

        for task in sorted(fixed, key=lambda item: item.fixed_start or day_start):
            start = task.fixed_start
            assert start is not None
            end = start + timedelta(minutes=task.estimated_duration_minutes)
            reason = self._invalid_slot_reason(
                task,
                start,
                end,
                day_start,
                day_end,
                existing + generated_blocks,
                body.minimum_buffer_minutes,
            )
            if reason:
                unscheduled.append(self._unscheduled(task, reason))
                continue
            item = self._score_item(
                task, start, existing + generated_blocks, profile, body, fixed=True
            )
            scheduled.append(item)
            generated_blocks.append(self._block_from_item(item))

        generated_minutes = sum(item["estimated_duration_minutes"] for item in scheduled)
        for task in flexible:
            if (
                existing_minutes + generated_minutes + task.estimated_duration_minutes
                > body.max_planned_minutes
            ):
                unscheduled.append(
                    self._unscheduled(
                        task,
                        f"Daily workload limit of {body.max_planned_minutes} minutes "
                        "would be exceeded.",
                    )
                )
                continue

            candidates: list[dict[str, Any]] = []
            cursor = day_start
            duration = timedelta(minutes=task.estimated_duration_minutes)
            while cursor + duration <= day_end:
                end = cursor + duration
                if not self._invalid_slot_reason(
                    task,
                    cursor,
                    end,
                    day_start,
                    day_end,
                    existing + generated_blocks,
                    body.minimum_buffer_minutes,
                ):
                    candidates.append(
                        self._score_item(
                            task,
                            cursor,
                            existing + generated_blocks,
                            profile,
                            body,
                        )
                    )
                cursor += timedelta(minutes=body.slot_interval_minutes)

            if not candidates:
                reason = (
                    "No conflict-free slot fits before the deadline."
                    if task.deadline_at is not None
                    else "Not enough conflict-free time remains inside your day boundaries."
                )
                unscheduled.append(self._unscheduled(task, reason))
                continue

            best = max(
                candidates,
                key=lambda item: (
                    item["final_score"],
                    -_parse_datetime(item["scheduled_start"]).timestamp(),
                ),
            )
            scheduled.append(best)
            generated_blocks.append(self._block_from_item(best))
            generated_minutes += task.estimated_duration_minutes

        scheduled.sort(key=lambda item: item["scheduled_start"])
        payload = {
            "user_id": str(user_id),
            "selected_date": body.selected_date.isoformat(),
            "timezone_name": body.timezone_name,
            "day_start": body.day_start.isoformat(),
            "day_end": body.day_end.isoformat(),
            "minimum_buffer_minutes": body.minimum_buffer_minutes,
            "slot_interval_minutes": body.slot_interval_minutes,
            "max_planned_minutes": body.max_planned_minutes,
            "max_focus_block_minutes": body.max_focus_block_minutes,
            "status": "draft",
            "request_snapshot": body.model_dump(mode="json"),
            "blocked_intervals": [self._serialize_block(block) for block in existing],
            "scheduled_tasks": scheduled,
            "unscheduled_tasks": unscheduled,
            "warnings": warnings,
            "confirmed_at": None,
        }
        return self.drafts.create(payload)

    def get(self, user_id: UUID, schedule_id: UUID) -> dict:
        draft = self.drafts.get_owned(schedule_id, user_id)
        if draft is None:
            raise ResourceNotFoundError("Daily schedule not found.")
        return draft

    def update(self, user_id: UUID, schedule_id: UUID, body: DailyScheduleUpdate) -> dict:
        draft = self.get(user_id, schedule_id)
        if draft["status"] != "draft":
            raise ResourceConflictError("A confirmed schedule can no longer be changed.")

        items = [dict(item) for item in draft.get("scheduled_tasks", [])]
        by_id = {str(item["task_id"]): item for item in items}
        for adjustment in body.adjustments:
            item = by_id.get(str(adjustment.task_id))
            if item is None:
                raise ResourceNotFoundError("Scheduled task not found in this draft.")
            if item.get("is_fixed_time"):
                raise DomainValidationError("Fixed-time tasks cannot be moved.")
            item["scheduled_start"] = adjustment.scheduled_start.isoformat()
            item["scheduled_end"] = (
                adjustment.scheduled_start
                + timedelta(minutes=int(item["estimated_duration_minutes"]))
            ).isoformat()
            item["explanation"] = (
                "Manually adjusted by you; the time remains conflict-free "
                "inside your daily availability."
            )

        tz = get_timezone(str(draft["timezone_name"]))
        selected = date.fromisoformat(str(draft["selected_date"]))
        start_clock = time.fromisoformat(str(draft["day_start"]))
        end_clock = time.fromisoformat(str(draft["day_end"]))
        day_start = datetime.combine(selected, start_clock, tzinfo=tz)
        day_end = datetime.combine(selected, end_clock, tzinfo=tz)
        buffer_minutes = int(draft["minimum_buffer_minutes"])
        blocked = [
            ScheduleBlock(
                _parse_datetime(row["start"]),
                _parse_datetime(row["end"]),
                str(row.get("title") or "Existing event"),
                int(row.get("required_focus", 3)),
                str(row.get("source") or "existing"),
            )
            for row in draft.get("blocked_intervals", [])
        ]
        validated: list[ScheduleBlock] = list(blocked)
        for item in sorted(items, key=lambda value: value["scheduled_start"]):
            start = _parse_datetime(item["scheduled_start"])
            end = _parse_datetime(item["scheduled_end"])
            if (
                as_local(start, str(draft["timezone_name"])).date() != selected
                or start < day_start
                or end > day_end
            ):
                raise DomainValidationError(
                    f"{item['title']} falls outside the selected day boundaries."
                )
            deadline = item.get("deadline_at")
            if deadline and end > _parse_datetime(deadline):
                raise DomainValidationError(f"{item['title']} would end after its deadline.")
            if self._conflicts(start, end, validated, buffer_minutes):
                raise DomainValidationError(f"{item['title']} overlaps another task or its buffer.")
            validated.append(self._block_from_item(item))

        items.sort(key=lambda item: item["scheduled_start"])
        return self.drafts.update(schedule_id, user_id, {"scheduled_tasks": items})

    def confirm(self, user_id: UUID, schedule_id: UUID) -> dict:
        draft = self.get(user_id, schedule_id)
        if draft["status"] == "confirmed":
            return draft

        scheduled = [dict(item) for item in draft.get("scheduled_tasks", [])]
        existing_count = len(
            self.tasks.list_for_user(str(user_id), date_filter=str(draft["selected_date"]))
        )
        total_count = existing_count + len(scheduled)
        for item in scheduled:
            start = as_local(_parse_datetime(item["scheduled_start"]), str(draft["timezone_name"]))
            task = self.tasks.create(
                str(user_id),
                {
                    "title": item["title"],
                    "notes": item["explanation"],
                    "task_category": item["category"],
                    "planned_start_time": start.strftime("%I:%M %p").lstrip("0"),
                    "planned_date": str(draft["selected_date"]),
                    "planned_duration_min": int(item["estimated_duration_minutes"]),
                    "importance": int(item["importance"]),
                    "energy_level": int(item["required_energy"]),
                    "focus_level": int(item["required_focus"]),
                    "total_tasks_today": total_count,
                    "timezone_name": str(draft["timezone_name"]),
                    "ai_plan_details": {
                        "difficulty": int(item["difficulty"]),
                        "deadline_at": item.get("deadline_at"),
                        "is_fixed_time": bool(item["is_fixed_time"]),
                    },
                },
            )
            item["created_task_id"] = task["id"]
            item["plan_input_id"] = task["ai_plan_input_id"]
            if self.calendar is not None:
                self.calendar.sync_task_safely(str(user_id), task)

        return self.drafts.update(
            schedule_id,
            user_id,
            {
                "status": "confirmed",
                "scheduled_tasks": scheduled,
                "confirmed_at": datetime.now(timezone.utc).isoformat(),
            },
        )

    def _existing_blocks(
        self,
        user_id: UUID,
        body: DailyScheduleGenerate,
        day_start: datetime,
        day_end: datetime,
    ) -> tuple[list[ScheduleBlock], list[str]]:
        blocks: list[ScheduleBlock] = []
        warnings: list[str] = []
        tz = get_timezone(body.timezone_name)
        for task in self.tasks.list_for_user(
            str(user_id), date_filter=body.selected_date.isoformat()
        ):
            if task.get("task_status") == "failed":
                continue
            parsed_time = self._parse_task_time(str(task["planned_start_time"]))
            start = datetime.combine(body.selected_date, parsed_time, tzinfo=tz)
            blocks.append(
                ScheduleBlock(
                    start,
                    start + timedelta(minutes=int(task["planned_duration_min"])),
                    str(task.get("title") or "Existing task"),
                    int(task.get("focus_level", 3)),
                    "task",
                )
            )

        rows = self.plans.list_schedule_rows(user_id)
        superseded = {
            str(row.get("parent_plan_input_id")) for row in rows if row.get("parent_plan_input_id")
        }
        occupied = {(block.start, block.end) for block in blocks}
        for row in rows:
            if str(row.get("id")) in superseded:
                continue
            start = _parse_datetime(row["planned_start"])
            end = start + timedelta(minutes=int(row["planned_duration_minutes"]))
            if as_local(start, body.timezone_name).date() != body.selected_date:
                continue
            if (start, end) in occupied:
                continue
            blocks.append(
                ScheduleBlock(
                    start,
                    end,
                    str(row.get("title") or "Existing AI plan"),
                    int(row.get("required_focus", 3)),
                    "ai_plan",
                )
            )
            occupied.add((start, end))

        if self.calendar is not None:
            try:
                for event in self.calendar.list_busy_events(str(user_id), day_start, day_end):
                    block = ScheduleBlock(
                        _parse_datetime(event["start"]),
                        _parse_datetime(event["end"]),
                        str(event.get("title") or "Google Calendar event"),
                        3,
                        "google_calendar",
                    )
                    if (block.start, block.end) not in occupied:
                        blocks.append(block)
                        occupied.add((block.start, block.end))
            except Exception:
                warnings.append(
                    "Google Calendar events could not be loaded; existing "
                    "HabitTrace plans were still protected."
                )
        return [
            block for block in blocks if block.start < day_end and block.end > day_start
        ], warnings

    def _score_item(
        self,
        task: DailyScheduleTaskInput,
        start: datetime,
        blocks: list[ScheduleBlock],
        profile: Any,
        body: DailyScheduleGenerate,
        *,
        fixed: bool = False,
    ) -> dict[str, Any]:
        context = self._schedule_context(start, task.estimated_duration_minutes, blocks)
        plan = {
            # The model contract accepts database-shaped plan snapshots even
            # though these candidates are intentionally not persisted yet.
            "id": str(task.client_id),
            "input_source": "user",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "title": task.title,
            "category": task.category,
            "planned_start": start.isoformat(),
            "planned_duration_minutes": task.estimated_duration_minutes,
            "deadline_at": task.deadline_at.isoformat() if task.deadline_at else None,
            "importance": task.importance,
            "difficulty": task.difficulty,
            "required_energy": task.required_energy,
            "required_focus": task.required_focus,
            "current_energy": task.required_energy,
            "current_focus": task.required_focus,
            "sleep_hours": None,
            "stress_level": None,
            "timezone_name": body.timezone_name,
            "is_fixed_time": task.is_fixed_time,
            **context,
        }
        base = self.model_service.predict(plan)
        result = self.personalization.apply(base, plan, profile)
        probability = float(result["success_probability"])
        daily_minutes = int(context["daily_planned_minutes"] or 0)
        overload_penalty = min(0.2, max(0.0, (daily_minutes - 360) / 1200))
        focus_penalty = self._focus_penalty(task, start, blocks, body)
        priority_bonus = task.importance * 0.01
        final_score = max(
            0.0, min(1.0, probability - overload_penalty - focus_penalty + priority_bonus)
        )
        clock = as_local(start, body.timezone_name).strftime("%-I:%M %p")
        if fixed:
            explanation = (
                f"Kept at {clock} because you marked it as fixed; the slot is conflict-free. "
                f"HabitTrace estimates a {round(probability * 100)}% success likelihood."
            )
        else:
            factors = ["it does not conflict with existing events"]
            if task.importance >= 4:
                factors.append("the task is high priority")
            if task.required_focus >= 4 and probability >= 0.65:
                factors.insert(0, "this is one of your stronger predicted focus times")
            elif probability >= 0.65:
                factors.insert(0, "your history indicates a stronger fit at this time")
            explanation = (
                f"Scheduled at {clock} because {', '.join(factors)}. "
                f"Estimated success likelihood: {round(probability * 100)}%."
            )
        return {
            "task_id": str(task.client_id),
            "title": task.title,
            "estimated_duration_minutes": task.estimated_duration_minutes,
            "deadline_at": task.deadline_at.isoformat() if task.deadline_at else None,
            "importance": task.importance,
            "category": task.category,
            "difficulty": task.difficulty,
            "required_energy": task.required_energy,
            "required_focus": task.required_focus,
            "is_fixed_time": task.is_fixed_time,
            "scheduled_start": start.isoformat(),
            "scheduled_end": (
                start + timedelta(minutes=task.estimated_duration_minutes)
            ).isoformat(),
            "predicted_success_probability": probability,
            "final_score": final_score,
            "explanation": explanation,
            "created_task_id": None,
            "plan_input_id": None,
        }

    @staticmethod
    def _priority_key(task: DailyScheduleTaskInput) -> tuple[datetime, int, int]:
        deadline = task.deadline_at or datetime.max.replace(tzinfo=timezone.utc)
        return deadline.astimezone(timezone.utc), -task.importance, -task.difficulty

    @staticmethod
    def _day_bounds(body: DailyScheduleGenerate) -> tuple[datetime, datetime]:
        tz = get_timezone(body.timezone_name)
        return (
            datetime.combine(body.selected_date, body.day_start, tzinfo=tz),
            datetime.combine(body.selected_date, body.day_end, tzinfo=tz),
        )

    @classmethod
    def _invalid_slot_reason(
        cls,
        task: DailyScheduleTaskInput,
        start: datetime,
        end: datetime,
        day_start: datetime,
        day_end: datetime,
        blocks: list[ScheduleBlock],
        buffer_minutes: int,
    ) -> str | None:
        if start < day_start or end > day_end:
            return "The fixed time falls outside your waking and sleeping boundaries."
        if task.deadline_at is not None and end > task.deadline_at:
            return "The task cannot finish before its deadline."
        if cls._conflicts(start, end, blocks, buffer_minutes):
            return "The requested time conflicts with an existing event or required buffer."
        return None

    @staticmethod
    def _conflicts(
        start: datetime,
        end: datetime,
        blocks: list[ScheduleBlock],
        buffer_minutes: int,
    ) -> bool:
        buffer = timedelta(minutes=buffer_minutes)
        return any(start < block.end + buffer and end + buffer > block.start for block in blocks)

    @staticmethod
    def _schedule_context(
        start: datetime,
        duration_minutes: int,
        blocks: list[ScheduleBlock],
    ) -> dict[str, int | None]:
        before = [block for block in blocks if block.start < start]
        minutes_before = sum(
            int((block.end - block.start).total_seconds() // 60) for block in before
        )
        daily_minutes = (
            sum(int((block.end - block.start).total_seconds() // 60) for block in blocks)
            + duration_minutes
        )
        gap: int | None = None
        if before:
            previous = max(before, key=lambda block: block.end)
            gap = max(0, int((start - previous.end).total_seconds() // 60))
        return {
            "tasks_before_count": len(before),
            "planned_minutes_before": minutes_before,
            "daily_planned_minutes": daily_minutes,
            "minutes_since_previous": gap,
        }

    @staticmethod
    def _focus_penalty(
        task: DailyScheduleTaskInput,
        start: datetime,
        blocks: list[ScheduleBlock],
        body: DailyScheduleGenerate,
    ) -> float:
        if task.required_focus < 4:
            return 0.0
        buffer = timedelta(minutes=body.minimum_buffer_minutes)
        total = task.estimated_duration_minutes
        end = start + timedelta(minutes=task.estimated_duration_minutes)
        for block in blocks:
            if block.required_focus >= 4 and (
                abs((start - block.end).total_seconds()) <= buffer.total_seconds()
                or abs((block.start - end).total_seconds()) <= buffer.total_seconds()
            ):
                total += int((block.end - block.start).total_seconds() // 60)
        return 0.15 if total > body.max_focus_block_minutes else 0.0

    @staticmethod
    def _covered_minutes(blocks: list[ScheduleBlock], start: datetime, end: datetime) -> int:
        intervals = sorted((max(start, block.start), min(end, block.end)) for block in blocks)
        total = 0
        cursor_start: datetime | None = None
        cursor_end: datetime | None = None
        for item_start, item_end in intervals:
            if item_end <= item_start:
                continue
            if cursor_start is None:
                cursor_start, cursor_end = item_start, item_end
            elif cursor_end is not None and item_start <= cursor_end:
                cursor_end = max(cursor_end, item_end)
            else:
                assert cursor_end is not None
                total += int((cursor_end - cursor_start).total_seconds() // 60)
                cursor_start, cursor_end = item_start, item_end
        if cursor_start is not None and cursor_end is not None:
            total += int((cursor_end - cursor_start).total_seconds() // 60)
        return total

    @staticmethod
    def _parse_task_time(value: str) -> time:
        for pattern in ("%I:%M %p", "%H:%M", "%H:%M:%S"):
            try:
                return datetime.strptime(value.strip().upper(), pattern).time()
            except ValueError:
                continue
        raise DomainValidationError("An existing task has an invalid start time.")

    @staticmethod
    def _unscheduled(task: DailyScheduleTaskInput, reason: str) -> dict[str, Any]:
        return {
            "task_id": str(task.client_id),
            "title": task.title,
            "estimated_duration_minutes": task.estimated_duration_minutes,
            "reason": reason,
        }

    @staticmethod
    def _block_from_item(item: dict[str, Any]) -> ScheduleBlock:
        return ScheduleBlock(
            _parse_datetime(item["scheduled_start"]),
            _parse_datetime(item["scheduled_end"]),
            str(item["title"]),
            int(item.get("required_focus", 3)),
            "generated",
        )

    @staticmethod
    def _serialize_block(block: ScheduleBlock) -> dict[str, Any]:
        return {
            "start": block.start.isoformat(),
            "end": block.end.isoformat(),
            "title": block.title,
            "required_focus": block.required_focus,
            "source": block.source,
        }
