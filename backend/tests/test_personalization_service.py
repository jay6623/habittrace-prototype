from __future__ import annotations

from datetime import datetime

from app.services.personalization_service import PersonalizationService

from .conftest import USER_ID
from .factories import plan_row


class HistoryPlansFake:
    def __init__(self, rows):
        self.rows = rows
        self.requested_user_id = None

    def list_completed_tasks(self, user_id):
        self.requested_user_id = user_id
        return self.rows


def history_row(index: int, *, completed: bool = True) -> dict:
    return {
        "id": f"history-{index}",
        "task_category": "work",
        "planned_start_time": "9:00 AM",
        "planned_date": f"2026-07-{10 + index:02d}",
        "planned_duration_min": 60,
        "task_status": "success" if completed else "failed",
        "created_at": f"2026-07-{10 + index:02d}T17:00:00+00:00",
    }


def test_no_history_keeps_shared_model_probability() -> None:
    service = PersonalizationService(HistoryPlansFake([]))
    profile = service.build_profile(USER_ID)
    result = service.apply(
        {"success_probability": 0.6},
        plan_row(),
        profile,
    )

    assert result["success_probability"] == 0.6
    assert result["personalization"]["applied"] is False
    assert result["personalization"]["sample_count"] == 0


def test_matching_success_history_increases_probability_gradually() -> None:
    repository = HistoryPlansFake([history_row(index) for index in range(1, 6)])
    service = PersonalizationService(repository)
    profile = service.build_profile(
        USER_ID,
        as_of=datetime.fromisoformat("2026-08-01T00:00:00+00:00"),
    )
    result = service.apply(
        {"success_probability": 0.5},
        plan_row(
            planned_start="2026-08-03T09:00:00-06:00",
            created_at="2026-08-01T00:00:00+00:00",
        ),
        profile,
    )

    assert repository.requested_user_id == USER_ID
    assert 0.5 < result["success_probability"] < 1.0
    assert result["base_success_probability"] == 0.5
    assert result["personalization"]["applied"] is True
    assert result["personalization"]["sample_count"] == 5
    assert result["personalization"]["confidence"] == 0.2
    assert result["personalization"]["factors"]


def test_target_plan_and_future_outcomes_are_excluded() -> None:
    target = history_row(1)
    target["id"] = "target"
    future = history_row(2)
    future["planned_date"] = "2027-01-01"
    service = PersonalizationService(HistoryPlansFake([target, future]))

    profile = service.build_profile(
        USER_ID,
        exclude_plan_id="target",
        as_of=datetime.fromisoformat("2026-08-01T00:00:00+00:00"),
    )

    assert profile.sample_count == 0
