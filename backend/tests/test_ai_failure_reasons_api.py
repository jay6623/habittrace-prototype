from __future__ import annotations

from fastapi.testclient import TestClient

from app.dependencies.ai_services import get_ai_failure_reason_service
from app.main import app

from .conftest import OUTCOME_ID


class FailureReasonServiceStub:
    def list_active(self):
        return [
            {
                "code": "low_readiness",
                "display_name": "Low readiness",
                "description": "Low energy, focus, or motivation affected execution.",
                "is_active": True,
            }
        ]

    def create_for_outcome(self, user_id, outcome_id, body):
        return {
            "outcome_id": outcome_id,
            "primary_reason_code": body.primary_reason_code,
            "secondary_reason_codes": body.secondary_reason_codes,
            "user_confirmed": True,
        }


def test_list_active_failure_reasons(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_failure_reason_service] = lambda: FailureReasonServiceStub()

    response = authenticated_client.get("/api/v2/ai/failure-reasons")

    assert response.status_code == 200
    assert response.json()[0]["code"] == "low_readiness"


def test_create_primary_and_secondary_reasons(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_failure_reason_service] = lambda: FailureReasonServiceStub()

    response = authenticated_client.post(
        f"/api/v2/ai/outcomes/{OUTCOME_ID}/failure-reasons",
        json={
            "primary_reason_code": "low_readiness",
            "secondary_reason_codes": ["interruption"],
        },
    )

    assert response.status_code == 201
    assert response.json()["primary_reason_code"] == "low_readiness"
    assert response.json()["user_confirmed"] is True


def test_rejects_primary_duplicated_as_secondary(
    authenticated_client: TestClient,
) -> None:
    app.dependency_overrides[get_ai_failure_reason_service] = lambda: FailureReasonServiceStub()

    response = authenticated_client.post(
        f"/api/v2/ai/outcomes/{OUTCOME_ID}/failure-reasons",
        json={
            "primary_reason_code": "interruption",
            "secondary_reason_codes": ["interruption"],
        },
    )

    assert response.status_code == 422


def test_rejects_client_supplied_confirmation(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_failure_reason_service] = lambda: FailureReasonServiceStub()

    response = authenticated_client.post(
        f"/api/v2/ai/outcomes/{OUTCOME_ID}/failure-reasons",
        json={
            "primary_reason_code": "interruption",
            "secondary_reason_codes": [],
            "user_confirmed": False,
        },
    )

    assert response.status_code == 422
