from __future__ import annotations

import pytest

from app.core.errors import DomainValidationError
from app.schemas.ai_time_recommendation import TimeRecommendationCreate
from app.services.ai_time_recommendation_service import AITimeRecommendationService

from .conftest import PLAN_ID, USER_ID


class PlansFake:
    def get_owned(self, plan_input_id, user_id):
        return {
            "id": str(plan_input_id),
            "user_id": str(user_id),
            "parent_plan_input_id": None,
            "planned_start": "2026-07-14T09:00:00+00:00",
            "planned_duration_minutes": 60,
            "category": "work",
            "input_source": "user",
            "importance": 3,
            "difficulty": 3,
            "required_energy": 3,
            "required_focus": 3,
            "current_energy": 3,
            "current_focus": 3,
            "sleep_hours": 7,
            "stress_level": 2,
            "deadline_at": None,
            "tasks_before_count": 0,
            "planned_minutes_before": 0,
            "daily_planned_minutes": 60,
            "minutes_since_previous": None,
            "timezone_name": "UTC",
            "is_fixed_time": False,
        }

    def list_schedule_rows(self, user_id):
        return [
            {
                "id": "other-plan",
                "parent_plan_input_id": None,
                "planned_start": "2026-07-14T10:00:00+00:00",
                "planned_duration_minutes": 60,
            }
        ]


class PredictionsFake:
    def ensure_model_version(self, model_type, version):
        return {"id": "model-version"}


class ModelFake:
    is_ready = True
    model_version = "test-model"

    def predict(self, plan):
        hour = int(str(plan["planned_start"])[11:13])
        probability = 0.9 if hour == 8 else 0.6
        return {
            "success_probability": probability,
            "predicted_failure_reason": "interruption",
        }


class RecommendationsFake:
    def __init__(self):
        self.recommendation = None
        self.candidates = []

    def create_recommendation(self, payload):
        self.recommendation = {
            "id": "recommendation-id",
            "created_at": "2026-07-14T00:00:00+00:00",
            **payload,
        }
        return self.recommendation

    def create_candidates(self, payload):
        self.candidates = [
            {"id": f"candidate-{i}", **row} for i, row in enumerate(payload, start=1)
        ]
        return self.candidates


def test_time_recommendation_filters_conflicts_and_ranks_candidates() -> None:
    recommendations = RecommendationsFake()
    service = AITimeRecommendationService(
        PlansFake(), recommendations, PredictionsFake(), ModelFake()
    )
    body = TimeRecommendationCreate(
        earliest_start="2026-07-14T08:00:00+00:00",
        latest_end="2026-07-14T12:00:00+00:00",
        slot_interval_minutes=60,
        minimum_buffer_minutes=15,
    )

    result = service.create(USER_ID, PLAN_ID, body)

    assert result["id"] == "recommendation-id"
    assert all(
        candidate["candidate_start"] != "2026-07-14T10:00:00+00:00"
        for candidate in result["candidates"]
    )
    assert result["candidates"][0]["rank"] == 1


def test_time_recommendation_rejects_window_shorter_than_plan() -> None:
    service = AITimeRecommendationService(
        PlansFake(), RecommendationsFake(), PredictionsFake(), ModelFake()
    )
    body = TimeRecommendationCreate(
        earliest_start="2026-07-14T08:00:00+00:00",
        latest_end="2026-07-14T08:30:00+00:00",
    )

    with pytest.raises(DomainValidationError):
        service.create(USER_ID, PLAN_ID, body)
