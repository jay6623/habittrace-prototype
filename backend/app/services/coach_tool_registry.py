"""Allowlisted execution of bounded AI Coach tools and safe proposals."""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Literal

from pydantic import BaseModel, ValidationError

from ..schemas.chat import PreferenceUpdate
from ..schemas.coach_tools import (
    FindAvailableTimesArgs,
    GetFailurePatternsArgs,
    GetScheduleArgs,
    GetTaskPerformanceArgs,
    GetUserPreferencesArgs,
    ToolCall,
    ToolDefinition,
    ToolResult,
)
from .coaching_context_service import CoachingContextService
from .coaching_planning_service import CoachingPlanningService

logger = logging.getLogger(__name__)


class CoachToolRegistry:
    """Owns the coach tool allowlist and injects trusted request context."""

    def __init__(
        self,
        context_service: CoachingContextService,
        planning_service: CoachingPlanningService | None = None,
    ) -> None:
        self.context_service = context_service
        self.planning_service = planning_service
        self._tools: dict[
            str,
            tuple[
                type[BaseModel],
                str,
                Literal["read", "proposal", "mutation"],
                Callable[[str, BaseModel, str, str | None], ToolResult],
            ],
        ] = {
            "get_task_performance": (
                GetTaskPerformanceArgs,
                "Get bounded task success/failure performance, optionally scoped by category "
                "or a case-insensitive title search. Can compare with the immediately preceding "
                "period and group results by hour or weekday.",
                "read",
                self._task_performance,
            ),
            "get_failure_patterns": (
                GetFailurePatternsArgs,
                "Get recorded failure reasons, interruptions, and planned-versus-actual duration "
                "evidence, optionally scoped by category or title.",
                "read",
                self._failure_patterns,
            ),
            "get_schedule": (
                GetScheduleArgs,
                "Get the user's pending scheduled tasks in a specific date range of at most "
                "31 days.",
                "read",
                self._schedule,
            ),
            "get_user_preferences": (
                GetUserPreferencesArgs,
                "Get saved coaching and scheduling preferences. Use only when those preferences "
                "are relevant to the user's question.",
                "read",
                self._preferences,
            ),
            "find_available_times": (
                FindAvailableTimesArgs,
                "Find conflict-free times using the user's schedule, preferences, and relevant "
                "performance. Use mode=suggest_times for informational advice, which never "
                "creates a proposal. Use mode=create_task_proposal only when the user explicitly "
                "asks to add or schedule a task; this creates a pending confirmation request, "
                "never a task. For follow-ups, reconstruct the complete planning request from "
                "recent user and assistant messages, retaining prior task, date, and duration "
                "unless changed and mapping a selected recommended time to exact_time. Treat "
                "requested periods and before/after/between times as hard earliest_time and/or "
                "latest_time constraints; never broaden them implicitly.",
                "proposal",
                self._available_times,
            ),
            "save_user_preferences": (
                PreferenceUpdate,
                "Save one or more explicitly requested coaching or scheduling preference "
                "changes. Use only when the user clearly asks to remember, set, or change a "
                "preference. Never infer a permanent preference from casual conversation. "
                "Only the schema's supported fields may be changed.",
                "mutation",
                self._save_preferences,
            ),
        }

    def definitions(self) -> list[ToolDefinition]:
        return [
            ToolDefinition(
                name=name,
                description=description,
                input_schema=schema.model_json_schema(),
                kind=kind,
            )
            for name, (schema, description, kind, _handler) in self._tools.items()
        ]

    def execute(
        self,
        call: ToolCall,
        *,
        user_id: str,
        timezone_name: str,
        conversation_id: str | None = None,
    ) -> ToolResult:
        registered = self._tools.get(call.name)
        if registered is None:
            logger.warning("AI Coach requested unknown tool %r", call.name)
            return ToolResult(name=call.name, ok=False, error="Unknown tool request.")

        schema, _description, _kind, handler = registered
        try:
            arguments = schema.model_validate(call.arguments)
        except ValidationError as exc:
            logger.warning("AI Coach supplied invalid arguments for %s: %s", call.name, exc)
            return ToolResult(name=call.name, ok=False, error="Invalid tool arguments.")

        try:
            return handler(user_id, arguments, timezone_name, conversation_id)
        except Exception:
            logger.exception("AI Coach tool %s failed", call.name)
            return ToolResult(
                name=call.name,
                ok=False,
                error="Tool data is temporarily unavailable.",
            )

    def execute_many(
        self,
        calls: list[ToolCall],
        *,
        user_id: str,
        timezone_name: str,
        conversation_id: str | None = None,
    ) -> list[ToolResult]:
        results: list[ToolResult] = []
        proposal_created = False
        for call in calls[:4]:
            if (
                proposal_created
                and call.name == "find_available_times"
                and call.arguments.get("mode") == "create_task_proposal"
            ):
                results.append(
                    ToolResult(
                        name=call.name,
                        ok=False,
                        error="Only one task proposal can be created per turn.",
                    )
                )
                continue
            result = self.execute(
                call,
                user_id=user_id,
                timezone_name=timezone_name,
                conversation_id=conversation_id,
            )
            results.append(result)
            proposal_created = proposal_created or result.proposal is not None
        return results

    def _task_performance(
        self,
        user_id: str,
        arguments: BaseModel,
        timezone_name: str,
        _conversation_id: str | None,
    ) -> ToolResult:
        parsed = GetTaskPerformanceArgs.model_validate(arguments)
        return ToolResult(
            name="get_task_performance",
            ok=True,
            data=self.context_service.get_task_performance(
                user_id,
                timezone_name=timezone_name,
                **parsed.model_dump(),
            ),
        )

    def _failure_patterns(
        self,
        user_id: str,
        arguments: BaseModel,
        timezone_name: str,
        _conversation_id: str | None,
    ) -> ToolResult:
        parsed = GetFailurePatternsArgs.model_validate(arguments)
        return ToolResult(
            name="get_failure_patterns",
            ok=True,
            data=self.context_service.get_failure_patterns(
                user_id,
                timezone_name=timezone_name,
                **parsed.model_dump(),
            ),
        )

    def _schedule(
        self,
        user_id: str,
        arguments: BaseModel,
        _timezone_name: str,
        _conversation_id: str | None,
    ) -> ToolResult:
        parsed = GetScheduleArgs.model_validate(arguments)
        return ToolResult(
            name="get_schedule",
            ok=True,
            data=self.context_service.get_schedule(
                user_id,
                start_date=parsed.start_date,
                end_date=parsed.end_date,
            ),
        )

    def _preferences(
        self,
        user_id: str,
        arguments: BaseModel,
        timezone_name: str,
        _conversation_id: str | None,
    ) -> ToolResult:
        GetUserPreferencesArgs.model_validate(arguments)
        return ToolResult(
            name="get_user_preferences",
            ok=True,
            data=self.context_service.get_preferences(user_id, timezone_name),
        )

    def _available_times(
        self,
        user_id: str,
        arguments: BaseModel,
        timezone_name: str,
        conversation_id: str | None,
    ) -> ToolResult:
        if not self.planning_service:
            return ToolResult(
                name="find_available_times",
                ok=False,
                error="Planning data is temporarily unavailable.",
            )
        parsed = FindAvailableTimesArgs.model_validate(arguments)
        outcome = self.planning_service.find_available_times(
            user_id,
            parsed,
            timezone_name=timezone_name,
            conversation_id=conversation_id,
        )
        return ToolResult(
            name="find_available_times",
            ok=True,
            data=outcome.data,
            proposal=outcome.proposal,
        )

    def _save_preferences(
        self,
        user_id: str,
        arguments: BaseModel,
        timezone_name: str,
        _conversation_id: str | None,
    ) -> ToolResult:
        updates = PreferenceUpdate.model_validate(arguments).model_dump(exclude_none=True)
        saved = self.context_service.save_preferences(user_id, updates, timezone_name)
        # Identity and storage metadata stay server-side and out of the final prompt.
        return ToolResult(
            name="save_user_preferences",
            ok=True,
            data={
                "saved_preferences": {
                    key: saved.get(key, value) for key, value in updates.items()
                }
            },
        )
