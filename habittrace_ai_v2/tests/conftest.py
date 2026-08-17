from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pandas as pd
import pytest

UTC = timezone.utc


@pytest.fixture
def plans() -> pd.DataFrame:
    base = datetime(2026, 1, 1, 12, tzinfo=UTC)
    rows: list[dict[str, object]] = []
    for index in range(30):
        planned_start = base + timedelta(hours=index * 6)
        rows.append(
            {
                "id": f"plan-{index}",
                "user_id": "user-1",
                "parent_plan_input_id": None,
                "input_source": "user" if index % 2 == 0 else "reschedule",
                "title": f"Plan {index}",
                "description": None,
                "category": "study" if index % 2 == 0 else "health",
                "planned_start": planned_start,
                "planned_duration_minutes": 20 + index,
                "deadline_at": planned_start + timedelta(hours=3) if index % 4 else None,
                "importance": 1 + index % 5,
                "difficulty": 1 + index % 5,
                "required_energy": 2 + index % 4,
                "required_focus": 3 + index % 3,
                "current_energy": None if index % 7 == 0 else 1 + index % 5,
                "current_focus": None if index % 6 == 0 else 1 + index % 5,
                "sleep_hours": None if index % 8 == 0 else 6.0 + (index % 4) * 0.5,
                "stress_level": None if index % 9 == 0 else 1 + index % 5,
                "tasks_before_count": index % 6,
                "planned_minutes_before": (index % 6) * 30,
                "daily_planned_minutes": 120 + (index % 6) * 30,
                "minutes_since_previous": None if index == 0 else 45 + index,
                "timezone_name": "America/Denver" if index % 2 == 0 else "Asia/Seoul",
                "is_fixed_time": index % 3 == 0,
                "created_at": planned_start - timedelta(days=1),
            }
        )
    return pd.DataFrame(rows)


@pytest.fixture
def outcomes(plans: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for index, plan in plans.iloc[:-1].iterrows():
        if index % 3 == 0:
            status, ratio = "completed", 0.9
        elif index % 3 == 1:
            status, ratio = "completed", 0.7
        else:
            status, ratio = "partial", 0.5
        actual_start = pd.Timestamp(plan["planned_start"]) + pd.Timedelta(minutes=5)
        rows.append(
            {
                "id": f"outcome-{index}",
                "plan_input_id": plan["id"],
                "outcome_status": status,
                "actual_start": actual_start,
                "actual_end": actual_start + pd.Timedelta(minutes=20),
                "active_minutes": 20,
                "completion_ratio": ratio,
                "interruption_count": index % 2,
                "stopped_early": status != "completed",
                "user_note": "post-outcome data",
                "recorded_at": actual_start + pd.Timedelta(hours=1),
            }
        )
    return pd.DataFrame(rows)


@pytest.fixture
def failure_reasons(outcomes: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for index, outcome in outcomes.iterrows():
        is_success = outcome["outcome_status"] == "completed" and outcome["completion_ratio"] >= 0.8
        if is_success:
            continue
        primary = "low_readiness" if index % 2 == 0 else "interruption"
        rows.extend(
            [
                {
                    "outcome_id": outcome["id"],
                    "reason_code": primary,
                    "is_primary": True,
                    "user_confirmed": True,
                    "created_at": outcome["recorded_at"] + pd.Timedelta(minutes=1),
                },
                {
                    "outcome_id": outcome["id"],
                    "reason_code": "schedule_overload",
                    "is_primary": False,
                    "user_confirmed": True,
                    "created_at": outcome["recorded_at"] + pd.Timedelta(minutes=2),
                },
                {
                    "outcome_id": outcome["id"],
                    "reason_code": "unexpected_event",
                    "is_primary": False,
                    "user_confirmed": False,
                    "created_at": outcome["recorded_at"] + pd.Timedelta(minutes=3),
                },
            ]
        )
    return pd.DataFrame(rows)
