"""Allowlisted execution of bounded, read-only AI Coach tools."""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

from pydantic import BaseModel, ValidationError

from ..schemas.coach_tools import (
    GetFailurePatternsArgs,
    GetScheduleArgs,
    GetTaskPerformanceArgs,
    GetUserPreferencesArgs,
    ToolCall,
    ToolDefinition,
    ToolResult,
)
from .coaching_context_service import CoachingContextService

logger = logging.getLogger(__name__)


class CoachToolRegistry:
    """Owns the complete Phase 1 tool allowlist and injects trusted request context."""

    def __init__(self, context_service: CoachingContextService) -> None:
        self.context_service = context_service
        self._tools: dict[
            str, tuple[type[BaseModel], str, Callable[[str, BaseModel, str], dict[str, Any]]]
        ] = {
            "get_task_performance": (
                GetTaskPerformanceArgs,
                "Get bounded task success/failure performance, optionally scoped by category "
                "or a case-insensitive title search. Can compare with the immediately preceding "
                "period and group results by hour or weekday.",
                self._task_performance,
            ),
            "get_failure_patterns": (
                GetFailurePatternsArgs,
                "Get recorded failure reasons, interruptions, and planned-versus-actual duration "
                "evidence, optionally scoped by category or title.",
                self._failure_patterns,
            ),
            "get_schedule": (
                GetScheduleArgs,
                "Get the user's pending scheduled tasks in a specific date range of at most "
                "31 days.",
                self._schedule,
            ),
            "get_user_preferences": (
                GetUserPreferencesArgs,
                "Get saved coaching and scheduling preferences. Use only when those preferences "
                "are relevant to the user's question.",
                self._preferences,
            ),
        }

    def definitions(self) -> list[ToolDefinition]:
        return [
            ToolDefinition(
                name=name,
                description=description,
                input_schema=schema.model_json_schema(),
            )
            for name, (schema, description, _handler) in self._tools.items()
        ]

    def execute(
        self,
        call: ToolCall,
        *,
        user_id: str,
        timezone_name: str,
    ) -> ToolResult:
        registered = self._tools.get(call.name)
        if registered is None:
            logger.warning("AI Coach requested unknown tool %r", call.name)
            return ToolResult(name=call.name, ok=False, error="Unknown tool request.")

        schema, _description, handler = registered
        try:
            arguments = schema.model_validate(call.arguments)
        except ValidationError as exc:
            logger.warning("AI Coach supplied invalid arguments for %s: %s", call.name, exc)
            return ToolResult(name=call.name, ok=False, error="Invalid tool arguments.")

        try:
            data = handler(user_id, arguments, timezone_name)
        except Exception:
            logger.exception("Read-only AI Coach tool %s failed", call.name)
            return ToolResult(
                name=call.name,
                ok=False,
                error="Tool data is temporarily unavailable.",
            )
        return ToolResult(name=call.name, ok=True, data=data)

    def execute_many(
        self,
        calls: list[ToolCall],
        *,
        user_id: str,
        timezone_name: str,
    ) -> list[ToolResult]:
        return [
            self.execute(call, user_id=user_id, timezone_name=timezone_name) for call in calls[:4]
        ]

    def _task_performance(
        self, user_id: str, arguments: BaseModel, timezone_name: str
    ) -> dict[str, Any]:
        parsed = GetTaskPerformanceArgs.model_validate(arguments)
        return self.context_service.get_task_performance(
            user_id,
            timezone_name=timezone_name,
            **parsed.model_dump(),
        )

    def _failure_patterns(
        self, user_id: str, arguments: BaseModel, timezone_name: str
    ) -> dict[str, Any]:
        parsed = GetFailurePatternsArgs.model_validate(arguments)
        return self.context_service.get_failure_patterns(
            user_id,
            timezone_name=timezone_name,
            **parsed.model_dump(),
        )

    def _schedule(
        self, user_id: str, arguments: BaseModel, _timezone_name: str
    ) -> dict[str, Any]:
        parsed = GetScheduleArgs.model_validate(arguments)
        return self.context_service.get_schedule(
            user_id,
            start_date=parsed.start_date,
            end_date=parsed.end_date,
        )

    def _preferences(
        self, user_id: str, arguments: BaseModel, timezone_name: str
    ) -> dict[str, Any]:
        GetUserPreferencesArgs.model_validate(arguments)
        return self.context_service.get_preferences(user_id, timezone_name)
