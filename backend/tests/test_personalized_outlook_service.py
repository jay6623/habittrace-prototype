from __future__ import annotations

from datetime import date

from app.repositories.personalization_repository import PersonalizationRepository
from app.services.personalization_service import PersonalizationService
from app.services.personalized_outlook_service import PersonalizedOutlookService

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase


class FakeModel:
    is_ready = True

    def predict(self, plan: dict) -> dict:
        assert {
            "input_source",
            "deadline_at",
            "sleep_hours",
            "stress_level",
            "created_at",
        } <= plan.keys()
        probability = 0.8 if plan["title"] == "Focused work" else 0.4
        return {
            "success_probability": probability,
            "predicted_failure_reason": (
                None if probability > 0.5 else "interruption"
            ),
            "failure_reason_probabilities": {"interruption": 0.6},
        }


def task(task_id: str, title: str, start: str, status: str = "pending") -> dict:
    return {
        "id": task_id,
        "user_id": str(USER_ID),
        "title": title,
        "task_category": "Work",
        "planned_date": "2026-09-10",
        "planned_start_time": start,
        "planned_duration_min": 60,
        "task_status": status,
        "importance": 4,
        "energy_level": 3,
        "focus_level": 4,
        "created_at": "2026-09-09T12:00:00+00:00",
    }


def test_outlook_scores_pending_tasks_and_uses_personal_history() -> None:
    rows = [
        task("one", "Focused work", "9:00 AM"),
        task("two", "Email cleanup", "11:00 AM"),
        {
            **task("history", "Past work", "9:00 AM", "success"),
            "planned_date": "2026-09-01",
        },
    ]
    db = MemoryDatabase({"tasks": rows})
    personalization = PersonalizationService(PersonalizationRepository(db))
    service = PersonalizedOutlookService(db, FakeModel(), personalization)

    result = service.get(USER_ID, date(2026, 9, 10), "America/Denver")

    assert result["available"] is True
    assert result["task_count"] == 2
    assert result["highest_potential"]["title"] == "Focused work"
    assert result["needs_attention"]["title"] == "Email cleanup"
    assert result["recommendation"]["code"] == "protect_time"
    assert result["personalization"]["sample_count"] == 1


def test_outlook_has_clear_empty_state() -> None:
    db = MemoryDatabase({"tasks": []})
    service = PersonalizedOutlookService(
        db,
        FakeModel(),
        PersonalizationService(PersonalizationRepository(db)),
    )

    result = service.get(USER_ID, date(2026, 9, 10), "UTC")

    assert result["available"] is False
    assert result["reason"] == "no_pending_plans"
    assert result["predicted_success_probability"] is None
