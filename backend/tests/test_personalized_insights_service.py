from __future__ import annotations

from datetime import date

from app.repositories.personalization_repository import PersonalizationRepository
from app.services.personalized_insights_service import PersonalizedInsightsService

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase


def outcome(
    task_id: str,
    planned_date: str,
    *,
    status: str,
    category: str = "Work",
    start: str = "9:00 AM",
    duration: int = 45,
) -> dict:
    return {
        "id": task_id,
        "user_id": str(USER_ID),
        "title": task_id,
        "task_category": category,
        "planned_date": planned_date,
        "planned_start_time": start,
        "planned_duration_min": duration,
        "task_status": status,
        "created_at": f"{planned_date}T12:00:00+00:00",
    }


def test_period_insights_compare_history_and_find_patterns() -> None:
    rows = [
        outcome("morning-1", "2026-09-10", status="success"),
        outcome("morning-2", "2026-09-09", status="success"),
        outcome(
            "night-1", "2026-09-08", status="failed", start="10:00 PM", duration=150
        ),
        outcome(
            "night-2", "2026-09-07", status="failed", start="10:00 PM", duration=150
        ),
        outcome("previous-1", "2026-09-03", status="failed"),
        outcome("previous-2", "2026-09-02", status="failed"),
    ]
    db = MemoryDatabase({"tasks": rows})
    service = PersonalizedInsightsService(PersonalizationRepository(db))

    result = service.get(USER_ID, "week", date(2026, 9, 10))

    assert result["available"] is True
    assert result["sample_count"] == 4
    assert result["success_rate"] == 50.0
    assert result["previous_success_rate"] == 0.0
    assert result["change_percentage_points"] == 50.0
    assert result["strongest_pattern"]["label"] == "morning"
    assert result["pattern_to_watch"]["label"] in {"night", "more than 2 hours"}


def test_period_insights_returns_learning_state_without_outcomes() -> None:
    db = MemoryDatabase({"tasks": []})
    service = PersonalizedInsightsService(PersonalizationRepository(db))

    result = service.get(USER_ID, "month", date(2026, 9, 10))

    assert result["available"] is False
    assert result["reason"] == "insufficient_data"
    assert result["confidence_label"] == "learning"
