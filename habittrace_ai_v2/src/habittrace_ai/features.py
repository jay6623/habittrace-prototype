"""Feature engineering using only information available when a plan was created."""

from __future__ import annotations

import math
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import numpy as np
import pandas as pd

from habittrace_ai.contracts import (
    REQUIRED_PLAN_COLUMNS,
    assert_no_forbidden_features,
    require_columns,
)

CATEGORICAL_FEATURE_COLUMNS: tuple[str, ...] = ("input_source", "category")

BASE_NUMERIC_COLUMNS: tuple[str, ...] = (
    "planned_duration_minutes",
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
)

MISSING_INDICATOR_SOURCES: tuple[str, ...] = (
    "deadline_at",
    "current_energy",
    "current_focus",
    "sleep_hours",
    "stress_level",
    "minutes_since_previous",
)

DERIVED_NUMERIC_COLUMNS: tuple[str, ...] = (
    "is_fixed_time",
    "planned_local_hour_sin",
    "planned_local_hour_cos",
    "planned_local_day_sin",
    "planned_local_day_cos",
    "planned_local_is_weekend",
    "deadline_slack_minutes",
    "energy_gap",
    "focus_gap",
) + tuple(f"{column}_missing" for column in MISSING_INDICATOR_SOURCES)

NUMERIC_FEATURE_COLUMNS: tuple[str, ...] = BASE_NUMERIC_COLUMNS + DERIVED_NUMERIC_COLUMNS
MODEL_FEATURE_COLUMNS: tuple[str, ...] = CATEGORICAL_FEATURE_COLUMNS + NUMERIC_FEATURE_COLUMNS


def _aware_datetime(value: object, *, field: str) -> datetime:
    raw: Any = value
    if raw is None or pd.isna(raw):
        raise ValueError(f"{field} must be a timezone-aware datetime")
    timestamp = pd.Timestamp(raw)
    result = timestamp.to_pydatetime()
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError(f"{field} must be timezone-aware")
    return result


def _local_start(value: object, timezone_name: object) -> datetime:
    planned_start = _aware_datetime(value, field="planned_start")
    raw_timezone: Any = timezone_name
    if raw_timezone is None or pd.isna(raw_timezone) or not str(raw_timezone).strip():
        raise ValueError("timezone_name must be a non-empty IANA timezone")
    try:
        timezone = ZoneInfo(str(timezone_name))
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"unknown timezone_name: {timezone_name}") from exc
    return planned_start.astimezone(timezone)


def _deadline_slack(deadline: object, planned_start: object) -> float:
    raw_deadline: Any = deadline
    if raw_deadline is None or pd.isna(raw_deadline):
        return float("nan")
    deadline_at = _aware_datetime(deadline, field="deadline_at")
    start = _aware_datetime(planned_start, field="planned_start")
    return (deadline_at - start).total_seconds() / 60.0


def build_plan_features(plans: pd.DataFrame) -> pd.DataFrame:
    """Transform plan snapshots into a stable, explicitly allow-listed feature frame."""

    require_columns(plans.columns, REQUIRED_PLAN_COLUMNS, name="plans")
    result = pd.DataFrame(index=plans.index)

    for column in CATEGORICAL_FEATURE_COLUMNS:
        values = plans[column]
        result[column] = values.where(values.notna(), np.nan).astype(object)
    for column in BASE_NUMERIC_COLUMNS:
        result[column] = pd.to_numeric(plans[column], errors="coerce")

    local_starts = [
        _local_start(start, timezone)
        for start, timezone in zip(
            plans["planned_start"],
            plans["timezone_name"],
            strict=True,
        )
    ]
    local_hours = np.array(
        [value.hour + value.minute / 60.0 + value.second / 3600.0 for value in local_starts]
    )
    result["is_fixed_time"] = plans["is_fixed_time"].astype("int8")
    result["planned_local_hour_sin"] = np.sin(2.0 * math.pi * local_hours / 24.0)
    result["planned_local_hour_cos"] = np.cos(2.0 * math.pi * local_hours / 24.0)
    local_days = np.array([value.weekday() for value in local_starts])
    result["planned_local_day_sin"] = np.sin(2.0 * math.pi * local_days / 7.0)
    result["planned_local_day_cos"] = np.cos(2.0 * math.pi * local_days / 7.0)
    result["planned_local_is_weekend"] = [int(value.weekday() >= 5) for value in local_starts]
    result["deadline_slack_minutes"] = [
        _deadline_slack(deadline, start)
        for deadline, start in zip(
            plans["deadline_at"],
            plans["planned_start"],
            strict=True,
        )
    ]
    result["energy_gap"] = result["required_energy"] - result["current_energy"]
    result["focus_gap"] = result["required_focus"] - result["current_focus"]

    for column in MISSING_INDICATOR_SOURCES:
        result[f"{column}_missing"] = plans[column].isna().astype("int8")

    result = pd.DataFrame(result.loc[:, list(MODEL_FEATURE_COLUMNS)])
    assert_no_forbidden_features(result.columns)
    return result
