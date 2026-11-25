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
    ResourceNotFoundError,
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

    def _linked_tasks(self, user_id: UUID, task_id: UUID) -> list[dict]:
        return (
            self.db.table("tasks")
            .select("*")
            .eq("user_id", str(user_id))
            .eq("source_group_task_id", str(task_id))
            .order("planned_date")
            .execute()
        ).data

    def _linked_task(
        self, user_id: UUID, task_id: UUID, body: GroupPersonalPlanRequest
    ) -> dict | None:
        rows = self._linked_tasks(user_id, task_id)
        if body.personal_task_id:
            row = next((r for r in rows if r["id"] == str(body.personal_task_id)), None)
            if row is None:
                raise ResourceNotFoundError("Personal block not found.")
            if row["task_status"] != "pending":
                raise ResourceConflictError(
                    "Recorded blocks cannot be rescheduled. Add a new block."
                )
            active = (
                self.db.table("executions")
                .select("id")
                .eq("user_id", str(user_id))
                .eq("task_id", row["id"])
                .is_("task_status", "null")
                .limit(1)
                .execute()
            ).data
            if active:
                raise ResourceConflictError("Finish the running block before rescheduling it.")
            return row
        return next(
            (
                r
                for r in rows
                if r.get("group_block_key", "00000000-0000-4000-8000-000000000001")
                == str(body.block_key)
            ),
            None,
        )

    @staticmethod
    def _snapshot(task: dict) -> dict:
        return {
            key: task.get(key)
            for key in ("due_date", "due_time", "due_timezone_name", "estimated_duration_minutes")
        }

    @staticmethod
    def _task_start(task: dict, timezone_name: str) -> datetime:
        for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
            try:
                clock = datetime.strptime(task["planned_start_time"].upper(), pattern).time()
                return datetime.combine(
                    datetime.fromisoformat(task["planned_date"]).date(),
                    clock,
                    get_timezone(task.get("timezone_name") or timezone_name),
                ).astimezone(UTC)
            except ValueError:
                continue
        raise ValueError("Unreadable plan time")

    def context(self, user_id: UUID, group_id: UUID, task_id: UUID) -> dict:
        task = self._assigned_task(user_id, group_id, task_id)
        rows = self._linked_tasks(user_id, task_id)
        blocks = []
        for row in rows:
            try:
                end = self._task_start(row, "UTC") + timedelta(minutes=row["planned_duration_min"])
                deadline = self._deadline(task, row.get("timezone_name") or "UTC")
                late = deadline is not None and end > deadline
            except ValueError:
                late = True
            blocks.append(
                {
                    "task": row,
                    "source_changed": row.get("group_source_snapshot") != self._snapshot(task),
                    "finishes_after_deadline": late,
                }
            )
        partial_progress = 0.0
        if rows:
            outcomes = (
                self.db.table("executions")
                .select("*")
                .eq("user_id", str(user_id))
                .in_("task_id", [r["id"] for r in rows])
                .order("created_at", desc=True)
                .execute()
            ).data or []
            latest = {}
            for outcome in sorted(
                outcomes, key=lambda o: (o.get("created_at", ""), o.get("id", "")), reverse=True
            ):
                latest.setdefault(outcome["task_id"], outcome)
            for row in rows:
                outcome = latest.get(row["id"], {})
                if row["task_status"] == "failed" and outcome.get("outcome_status") == "partial":
                    partial_progress += row["planned_duration_min"] * float(
                        outcome.get("completion_ratio") or 0
                    )
        partial_minutes = int(partial_progress)
        planned = (
            sum(r["planned_duration_min"] for r in rows if r["task_status"] != "failed")
            + partial_minutes
        )
        completed = sum(r["planned_duration_min"] for r in rows if r["task_status"] == "success")
        estimate = task.get("estimated_duration_minutes")
        own = next((a for a in task["assignees"] if a["user_id"] == str(user_id)), {})
        return {
            "group_task": task,
            "blocks": blocks,
            "planned_minutes": planned,
            "completed_minutes": completed,
            "partial_progress_minutes": partial_minutes,
            "remaining_minutes": max(0, estimate - planned) if estimate else None,
            "can_share_completion": (
                bool(rows)
                and all(r["task_status"] != "pending" for r in rows)
                and completed > 0
                and (not estimate or completed + partial_minutes >= estimate)
            ),
            "shared_outcome": own.get("outcome"),
        }

    def reviews(self, user_id: UUID) -> list[dict]:
        result = []
        linked_ids = {
            str(r["source_group_task_id"])
            for r in self.tasks.list_for_user(str(user_id))
            if r.get("source_group_task_id")
        }
        if not linked_ids:
            return result
        for membership in self.groups.groups.list_memberships_for_user(str(user_id)):
            group_id = UUID(str(membership["group_id"]))
            for task in self.groups.groups.list_tasks(str(group_id)):
                if str(task["id"]) not in linked_ids:
                    continue
                assignees = self.groups._task_assignee_ids(str(group_id), str(task["id"]), task)
                if str(user_id) not in assignees:
                    continue
                context = self.context(user_id, group_id, UUID(str(task["id"])))
                if any(b["source_changed"] for b in context["blocks"]) or (
                    context["can_share_completion"] and context["shared_outcome"] != "success"
                ):
                    result.append(context)
        return result

    def acknowledge(
        self, user_id: UUID, group_id: UUID, task_id: UUID, source_version: str
    ) -> dict:
        context = self.context(user_id, group_id, task_id)
        if context["group_task"]["updated_at"] != source_version:
            raise ResourceConflictError(
                "The group task changed again. Review it before acknowledging."
            )
        if any(
            b["finishes_after_deadline"] and b["task"]["task_status"] == "pending"
            for b in context["blocks"]
        ):
            raise ResourceConflictError("Move blocks before the new deadline before acknowledging.")
        for row in self._linked_tasks(user_id, task_id):
            changes = {"group_source_snapshot": self._snapshot(context["group_task"])}
            if row["task_status"] == "pending":
                deadline = self._deadline(context["group_task"], row.get("timezone_name") or "UTC")
                changes["ai_plan_details"] = {
                    **row.get("ai_plan_details", {}),
                    "deadline_at": deadline.isoformat() if deadline else None,
                }
                if (
                    self.tasks.update(str(user_id), row["id"], changes, require_pending=True)
                    is None
                ):
                    raise ResourceConflictError(
                        "A block was recorded during review. Refresh and retry."
                    )
            else:
                # Historical inputs/outcomes are immutable; only mark the change as reviewed.
                self.db.table("tasks").update(changes).eq("id", row["id"]).eq(
                    "user_id", str(user_id)
                ).execute()
        return self.context(user_id, group_id, task_id)

    def share_completion(self, user_id: UUID, group_id: UUID, task_id: UUID) -> dict:
        context = self.context(user_id, group_id, task_id)
        if not context["can_share_completion"]:
            raise ResourceConflictError(
                "Complete all your personal blocks before sharing completion."
            )
        # This is a separate, explicit publication; it creates no execution or training label.
        updated = self.groups.groups.set_assignee_outcome(
            str(group_id), str(task_id), str(user_id), "success", datetime.now(UTC).isoformat()
        )
        if updated is None:
            raise ResourceNotFoundError("Task assignment not found.")
        return self.context(user_id, group_id, task_id)

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

    def _blocks(
        self, user_id: UUID, body: GroupPersonalPlanRequest, *, search_end: datetime | None = None
    ) -> tuple[list, list[str]]:
        blocks = []
        warnings = []
        for task in self.tasks.list_for_user(str(user_id)):
            if task.get("task_status") == "failed" or task["id"] == str(body.personal_task_id):
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
            search_end or day_end,
            body.planned_start.astimezone(UTC) + timedelta(minutes=body.planned_duration_minutes),
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
        day_start = datetime.combine(day, time.min, tz).astimezone(UTC)
        day_end = datetime.combine(day + timedelta(days=1), time.min, tz).astimezone(UTC)
        # Clip overnight / all-day events and merge overlap to avoid counting busy time twice.
        intervals = sorted(
            (max(a, day_start), min(b, day_end))
            for a, b, _ in blocks
            if a < day_end and b > day_start
        )
        daily: list[tuple[datetime, datetime]] = []
        for a, b in intervals:
            if daily and a <= daily[-1][1]:
                daily[-1] = (daily[-1][0], max(b, daily[-1][1]))
            else:
                daily.append((a, b))
        before = [(a, b) for a, b in daily if a < start]
        previous = max((b for _, b in before), default=None)
        deadline = self._deadline(task, body.timezone_name)
        return {
            "id": str(body.personal_task_id or "group-personal-preview"),
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
        *,
        plan: dict | None = None,
    ) -> dict:
        plan = self._plan(task, body, blocks) if plan is None else plan
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
        linked = self._linked_task(user_id, task_id, body)
        if linked and not body.personal_task_id:
            return {"personal_task": linked}
        self._validate_window(task, body)
        tz = get_timezone(body.timezone_name)
        day = body.planned_start.astimezone(tz).date()
        deadline = self._deadline(task, body.timezone_name)
        last = day + timedelta(days=body.search_days - 1)
        if deadline:
            last = min(last, deadline.astimezone(tz).date())
        search_end = datetime.combine(last + timedelta(days=1), time.min, tz)
        blocks, warnings = self._blocks(user_id, body, search_end=search_end)
        result: dict = {
            "personal_task": linked,
            "conflicts": self._conflicts(body.planned_start, body.planned_duration_minutes, blocks),
            "warnings": warnings,
            "candidates": [],
            "search_start": day.isoformat(),
            "search_end": last.isoformat(),
        }
        profile = None
        scoring = self.model.is_ready
        try:
            if scoring:
                profile = (
                    self.personalization.build_profile(
                        user_id, exclude_plan_id=body.personal_task_id
                    )
                    if body.personal_task_id
                    else self.personalization.build_profile(user_id)
                )
                result["prediction"] = self._score(task, body, blocks, profile)
        except (ValueError, TypeError, RuntimeError, RepositoryError, DatabaseUnavailableError):
            logger.warning("Group personal prediction unavailable", exc_info=True)
            scoring = False
        if not scoring:
            warnings.append("Prediction is unavailable. Available times are still shown.")
        # Keep each day's best option, then compare days so alternatives cover multiple dates.
        candidates = []
        all_candidates = []
        now = datetime.now(UTC)
        for offset in range((last - day).days + 1):
            candidate_day = day + timedelta(days=offset)
            daily_candidates = []
            for minute in range(8 * 60, 22 * 60, 30):
                start = datetime.combine(candidate_day, time(minute // 60, minute % 60), tz)
                end = start.astimezone(UTC) + timedelta(minutes=body.planned_duration_minutes)
                if start == body.planned_start or start <= now:
                    continue
                if end > datetime.combine(candidate_day, time(22), tz).astimezone(UTC):
                    continue
                if deadline and end > deadline:
                    continue
                if self._conflicts(start, body.planned_duration_minutes, blocks):
                    continue
                candidate = body.model_copy(update={"planned_start": start.astimezone(UTC)})
                probability = None
                if scoring:
                    try:
                        probability = self._score(task, candidate, blocks, profile)[
                            "success_probability"
                        ]
                    except (
                        ValueError,
                        TypeError,
                        RuntimeError,
                        RepositoryError,
                        DatabaseUnavailableError,
                    ):
                        scoring = False
                        warnings.append("Some times could not be scored; review availability.")
                daily_candidates.append(
                    {
                        "planned_start": start.astimezone(UTC).isoformat(),
                        "success_probability": probability,
                        "daily_planned_minutes": self._plan(task, candidate, blocks)[
                            "daily_planned_minutes"
                        ],
                        "deadline_slack_minutes": int((deadline - end).total_seconds() // 60)
                        if deadline
                        else None,
                    }
                )
            all_candidates.extend(daily_candidates)
            if daily_candidates:
                candidates.append(min(daily_candidates, key=self._candidate_order))
        if len(candidates) < 3:
            # A near deadline may leave only one day. Offer other slots on that day too.
            extras = sorted(
                (c for c in all_candidates if c not in candidates), key=self._candidate_order
            )
            candidates.extend(extras[: 3 - len(candidates)])
        result["candidates"] = sorted(candidates, key=self._candidate_order)[:3]
        return result

    @staticmethod
    def _candidate_order(candidate: dict) -> tuple:
        score = candidate["success_probability"]
        return (
            -(score if score is not None else -1),
            candidate["daily_planned_minutes"],
            candidate["planned_start"],
        )

    def confirm(
        self, user_id: UUID, group_id: UUID, task_id: UUID, body: GroupPersonalPlanRequest
    ) -> dict:
        task = self._assigned_task(user_id, group_id, task_id)
        linked = self._linked_task(user_id, task_id, body)
        if linked and not body.personal_task_id:
            return linked
        if (
            body.expected_source_updated_at is not None
            and body.expected_source_updated_at != task.get("updated_at")
        ):
            raise ResourceConflictError("The group task changed. Review its new deadline first.")
        self._validate_window(task, body)
        blocks, _warnings = self._blocks(user_id, body)
        if self._conflicts(body.planned_start, body.planned_duration_minutes, blocks):
            linked = self._linked_task(user_id, task_id, body)
            if linked and not body.personal_task_id:
                return linked
            raise ResourceConflictError("This time overlaps another plan. Choose another time.")
        plan = self._plan(task, body, blocks)
        local_start = body.planned_start.astimezone(get_timezone(body.timezone_name))
        payload = {
            "source_group_task_id": str(task_id),
            "group_block_key": str(body.block_key),
            "group_source_snapshot": self._snapshot(task),
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
            if body.personal_task_id:
                payload.pop("source_group_task_id")
                payload.pop("group_block_key")
                created = self.tasks.update(
                    str(user_id), str(body.personal_task_id), payload, require_pending=True
                )
                if created is None:
                    raise ResourceConflictError(
                        "This block was recorded or removed. Refresh your plans."
                    )
            else:
                created = self.tasks.create(str(user_id), payload)
        except APIError as exc:
            if exc.code != "23505":
                raise
            linked = self._linked_task(user_id, task_id, body)
            if linked is None:
                raise
            return linked
        self.calendar.sync_task_safely(str(user_id), created)
        return created
