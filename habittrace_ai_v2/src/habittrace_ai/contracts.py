"""Shared data contracts for the AI-only database schema."""

from __future__ import annotations

from collections.abc import Iterable

FAILURE_REASON_CODES: tuple[str, ...] = (
    "low_readiness",
    "schedule_overload",
    "underestimated_time",
    "interruption",
    "unexpected_event",
    "unclear_plan",
    "task_too_difficult",
    "other",
)

OUTCOME_STATUSES: frozenset[str] = frozenset({"not_started", "partial", "completed", "abandoned"})

PLAN_TABLE_COLUMNS: tuple[str, ...] = (
    "id",
    "user_id",
    "parent_plan_input_id",
    "input_source",
    "title",
    "description",
    "category",
    "planned_start",
    "planned_duration_minutes",
    "deadline_at",
    "importance",
    "difficulty",
    "required_energy",
    "required_focus",
    "current_energy",
    "current_focus",
    "sleep_hours",
    "stress_level",
    "tasks_before_count",
    "planned_minutes_before",
    "daily_planned_minutes",
    "minutes_since_previous",
    "timezone_name",
    "is_fixed_time",
    "created_at",
)

REQUIRED_PLAN_COLUMNS: frozenset[str] = frozenset(
    {
        "id",
        "input_source",
        "category",
        "planned_start",
        "planned_duration_minutes",
        "deadline_at",
        "importance",
        "difficulty",
        "required_energy",
        "required_focus",
        "current_energy",
        "current_focus",
        "sleep_hours",
        "stress_level",
        "tasks_before_count",
        "planned_minutes_before",
        "daily_planned_minutes",
        "minutes_since_previous",
        "timezone_name",
        "is_fixed_time",
        "created_at",
    }
)

REQUIRED_OUTCOME_COLUMNS: frozenset[str] = frozenset(
    {"id", "plan_input_id", "outcome_status", "completion_ratio", "recorded_at"}
)

REQUIRED_FAILURE_REASON_COLUMNS: frozenset[str] = frozenset(
    {"outcome_id", "reason_code", "is_primary", "user_confirmed", "created_at"}
)

# These values are known only during or after execution and must never enter predictors.
FORBIDDEN_FEATURE_COLUMNS: frozenset[str] = frozenset(
    {
        "outcome_id",
        "plan_input_id",
        "outcome_status",
        "actual_start",
        "actual_end",
        "active_minutes",
        "completion_ratio",
        "interruption_count",
        "stopped_early",
        "user_note",
        "recorded_at",
        "outcome_recorded_at",
        "label_available_at",
        "reason_created_at",
        "reason_code",
        "is_primary",
        "user_confirmed",
        "success_label",
    }
)


def require_columns(columns: Iterable[str], required: Iterable[str], *, name: str) -> None:
    """Raise a readable error when a database-shaped frame is incomplete."""

    available = set(columns)
    missing = sorted(set(required) - available)
    if missing:
        raise ValueError(f"{name} is missing required columns: {', '.join(missing)}")


def assert_no_forbidden_features(columns: Iterable[str]) -> None:
    """Fail closed if post-outcome data reaches a model feature frame."""

    leaked = sorted(set(columns) & FORBIDDEN_FEATURE_COLUMNS)
    if leaked:
        raise ValueError(f"post-outcome columns cannot be model features: {', '.join(leaked)}")
