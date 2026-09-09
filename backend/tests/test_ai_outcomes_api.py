from __future__ import annotations

from fastapi.testclient import TestClient

from app.core.errors import ResourceConflictError
from app.dependencies.ai_services import get_ai_outcome_service
from app.main import app

from .conftest import PLAN_ID
from .factories import outcome_row


class OutcomeServiceStub:
    def __init__(self, *, conflict: bool = False) -> None:
        self.conflict = conflict

    def create(self, user_id, plan_input_id, body):
        if self.conflict:
            raise ResourceConflictError("This plan already has an outcome.")
        return outcome_row(
            plan_input_id=str(plan_input_id),
            outcome_status=body.outcome_status.value,
            completion_ratio=float(body.completion_ratio),
        )


def test_create_outcome(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_outcome_service] = lambda: OutcomeServiceStub()
    payload = {
        "outcome_status": "partial",
        "actual_start": "2026-07-14T09:05:00-06:00",
        "actual_end": "2026-07-14T09:45:00-06:00",
        "active_minutes": 35,
        "completion_ratio": 0.6,
        "interruption_count": 1,
        "stopped_early": True,
    }

    response = authenticated_client.post(f"/api/v2/ai/plans/{PLAN_ID}/outcome", json=payload)

    assert response.status_code == 201
    assert response.json()["outcome_status"] == "partial"


def test_duplicate_outcome_returns_409(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_outcome_service] = lambda: OutcomeServiceStub(conflict=True)

    response = authenticated_client.post(
        f"/api/v2/ai/plans/{PLAN_ID}/outcome",
        json={"outcome_status": "not_started", "completion_ratio": 0},
    )

    assert response.status_code == 409
    assert response.json()["code"] == "conflict"


def test_not_started_rejects_execution_data(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_outcome_service] = lambda: OutcomeServiceStub()

    response = authenticated_client.post(
        f"/api/v2/ai/plans/{PLAN_ID}/outcome",
        json={
            "outcome_status": "not_started",
            "completion_ratio": 0,
            "active_minutes": 5,
        },
    )

    assert response.status_code == 422


def test_outcome_rejects_end_before_start(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_outcome_service] = lambda: OutcomeServiceStub()

    response = authenticated_client.post(
        f"/api/v2/ai/plans/{PLAN_ID}/outcome",
        json={
            "outcome_status": "partial",
            "actual_start": "2026-07-14T10:00:00-06:00",
            "actual_end": "2026-07-14T09:00:00-06:00",
            "completion_ratio": 0.5,
        },
    )

    assert response.status_code == 422
