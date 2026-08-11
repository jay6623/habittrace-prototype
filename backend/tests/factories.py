from __future__ import annotations

from copy import deepcopy

from .conftest import OUTCOME_ID, PLAN_ID, USER_ID

_PLAN = {
    "id": str(PLAN_ID),
    "user_id": str(USER_ID),
    "parent_plan_input_id": None,
    "input_source": "user",
    "title": "Write project report",
    "description": None,
    "category": "work",
    "planned_start": "2026-07-14T09:00:00-06:00",
    "planned_duration_minutes": 60,
    "deadline_at": "2026-07-14T17:00:00-06:00",
    "importance": 4,
    "difficulty": 3,
    "required_energy": 3,
    "required_focus": 4,
    "current_energy": 3,
    "current_focus": 4,
    "sleep_hours": 7.5,
    "stress_level": 2,
    "tasks_before_count": 1,
    "planned_minutes_before": 30,
    "daily_planned_minutes": 90,
    "minutes_since_previous": 15,
    "timezone_name": "America/Denver",
    "is_fixed_time": False,
    "created_at": "2026-07-13T12:00:00+00:00",
}

_OUTCOME = {
    "id": str(OUTCOME_ID),
    "plan_input_id": str(PLAN_ID),
    "outcome_status": "partial",
    "actual_start": "2026-07-14T09:05:00-06:00",
    "actual_end": "2026-07-14T09:45:00-06:00",
    "active_minutes": 35,
    "completion_ratio": 0.6,
    "interruption_count": 1,
    "stopped_early": True,
    "user_note": None,
    "recorded_at": "2026-07-14T16:00:00+00:00",
}


def plan_row(**updates):
    row = deepcopy(_PLAN)
    row.update(updates)
    return row


def outcome_row(**updates):
    row = deepcopy(_OUTCOME)
    row.update(updates)
    return row
