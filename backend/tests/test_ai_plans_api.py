from __future__ import annotations

from fastapi.testclient import TestClient

from app.core.errors import ResourceNotFoundError
from app.dependencies.ai_services import get_ai_plan_service
from app.main import app

from .conftest import PLAN_ID, USER_ID
from .factories import plan_row


class PlanServiceStub:
    def __init__(self) -> None:
        self.created_with = None

    def create(self, user_id, body):
        self.created_with = (user_id, body)
        return plan_row(title=body.title)

    def get(self, user_id, plan_input_id):
        if str(plan_input_id) != str(PLAN_ID):
            raise ResourceNotFoundError("Plan not found.")
        return plan_row()


def valid_plan_payload() -> dict:
    return {
        "title": "Write project report",
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
        "timezone_name": "America/Denver",
    }


def test_create_plan_uses_authenticated_user(authenticated_client: TestClient) -> None:
    service = PlanServiceStub()
    app.dependency_overrides[get_ai_plan_service] = lambda: service

    response = authenticated_client.post("/api/v2/ai/plans", json=valid_plan_payload())

    assert response.status_code == 201
    assert response.json()["id"] == str(PLAN_ID)
    assert service.created_with[0] == USER_ID


def test_create_plan_rejects_body_user_id(authenticated_client: TestClient) -> None:
    service = PlanServiceStub()
    app.dependency_overrides[get_ai_plan_service] = lambda: service
    payload = valid_plan_payload()
    payload["user_id"] = "99999999-9999-4999-8999-999999999999"

    response = authenticated_client.post("/api/v2/ai/plans", json=payload)

    assert response.status_code == 422
    assert service.created_with is None


def test_create_plan_rejects_naive_datetime(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_plan_service] = lambda: PlanServiceStub()
    payload = valid_plan_payload()
    payload["planned_start"] = "2026-07-14T09:00:00"

    response = authenticated_client.post("/api/v2/ai/plans", json=payload)

    assert response.status_code == 422


def test_create_plan_rejects_invalid_timezone(authenticated_client: TestClient) -> None:
    app.dependency_overrides[get_ai_plan_service] = lambda: PlanServiceStub()
    payload = valid_plan_payload()
    payload["timezone_name"] = "Mars/Olympus"

    response = authenticated_client.post("/api/v2/ai/plans", json=payload)

    assert response.status_code == 422


def test_get_non_owned_or_missing_plan_returns_404(
    authenticated_client: TestClient,
) -> None:
    app.dependency_overrides[get_ai_plan_service] = lambda: PlanServiceStub()

    response = authenticated_client.get(
        "/api/v2/ai/plans/99999999-9999-4999-8999-999999999999"
    )

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"
