"""Validated availability lookup and confirmation-gated task proposal preparation."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from ..schemas.chat import PlanDraft
from ..schemas.coach_tools import FindAvailableTimesArgs
from .coach_repository import CoachRepository
from .coaching_context_service import CoachingContextService
from .coaching_recommendation_service import CoachingRecommendationService


@dataclass(frozen=True)
class PlanningToolOutcome:
    data: dict[str, Any]
    proposal: dict[str, Any] | None = None


class CoachingPlanningService:
    """Adapts existing scheduling services to the provider-neutral planning tool."""

    def __init__(
        self,
        context_service: CoachingContextService,
        recommender: CoachingRecommendationService,
        repository: CoachRepository | None,
    ) -> None:
        self.context_service = context_service
        self.recommender = recommender
        self.repository = repository

    def find_available_times(
        self,
        user_id: str,
        arguments: FindAvailableTimesArgs,
        *,
        timezone_name: str,
        conversation_id: str | None,
    ) -> PlanningToolOutcome:
        missing = self._missing_fields(arguments)
        if missing:
            return PlanningToolOutcome(
                data={
                    "status": "needs_clarification",
                    "missing_fields": missing,
                    "requested_mode": arguments.mode,
                }
            )

        assert arguments.planned_date is not None
        assert arguments.duration_minutes is not None
        try:
            user_timezone = ZoneInfo(timezone_name)
        except ZoneInfoNotFoundError:
            user_timezone = ZoneInfo("UTC")
        now = datetime.now(user_timezone)
        today = now.date()
        if arguments.planned_date < today:
            return PlanningToolOutcome(
                data={
                    "status": "invalid_request",
                    "reason": "planned_date cannot be in the past",
                }
            )

        draft = PlanDraft.model_validate(
            {
                **arguments.model_dump(exclude={"mode"}),
                "planned_date": arguments.planned_date.isoformat(),
            }
        )
        schedule = self.context_service.get_schedule(
            user_id,
            start_date=arguments.planned_date,
            end_date=arguments.planned_date,
        )
        preferences = self.context_service.get_preferences(user_id, timezone_name)
        performance = self.context_service.get_task_performance(
            user_id,
            timezone_name=timezone_name,
            category=arguments.category,
            period_days=90,
            group_by=["hour"],
        )
        current_performance = performance.get("current") or {}
        context = {
            "preferences": preferences,
            "last_30_days": current_performance,
            "hour_patterns": performance.get("by_hour") or [],
            "category_patterns": [
                {"category": arguments.category, **current_performance}
            ],
            "upcoming_schedule": schedule.get("tasks") or [],
        }
        options = self.recommender.recommend(draft.model_dump(), context)
        if arguments.planned_date == today:
            options = [
                option
                for option in options
                if datetime.fromisoformat(str(option["start"])).astimezone(user_timezone) > now
            ]
        if not options:
            return PlanningToolOutcome(
                data={
                    "status": "no_availability",
                    "date": arguments.planned_date.isoformat(),
                    "duration_minutes": arguments.duration_minutes,
                }
            )

        data = {
            "status": "options_found",
            "mode": arguments.mode,
            "date": arguments.planned_date.isoformat(),
            "duration_minutes": arguments.duration_minutes,
            "options": options,
        }
        if arguments.mode == "suggest_times":
            return PlanningToolOutcome(data=data)

        if not self.repository:
            return PlanningToolOutcome(
                data={
                    **data,
                    "status": "proposal_unavailable",
                    "reason": "proposal persistence is unavailable",
                }
            )

        task = self._task_payload(draft, options, schedule.get("tasks") or [])
        proposal_payload = {"task": task, "options": options}
        proposal = self.repository.create_proposal(
            user_id,
            conversation_id,
            proposal_payload,
        )
        proposal_event = {
            "id": proposal["id"],
            "task": task,
            "options": options,
        }
        return PlanningToolOutcome(
            data={
                **data,
                "status": "proposal_created",
                "confirmation_required": True,
            },
            proposal=proposal_event,
        )

    @staticmethod
    def _missing_fields(arguments: FindAvailableTimesArgs) -> list[str]:
        missing = []
        if arguments.planned_date is None:
            missing.append("planned_date")
        if arguments.duration_minutes is None:
            missing.append("duration_minutes")
        if arguments.mode == "create_task_proposal" and not arguments.title:
            missing.append("title")
        return missing

    @staticmethod
    def _task_payload(
        draft: PlanDraft,
        options: list[dict[str, Any]],
        scheduled_tasks: list[dict[str, Any]],
    ) -> dict[str, Any]:
        assert draft.title is not None
        assert draft.planned_date is not None
        first_clock = str(options[0]["start"])[11:16]
        return {
            "title": draft.title,
            "task_category": draft.category,
            "planned_start_time": first_clock,
            "planned_date": draft.planned_date,
            "planned_duration_min": draft.duration_minutes,
            "importance": draft.importance,
            "energy_level": draft.energy_level,
            "focus_level": draft.focus_level,
            "total_tasks_today": 1
            + sum(item.get("date") == draft.planned_date for item in scheduled_tasks),
        }
