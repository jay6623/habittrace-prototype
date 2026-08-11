from __future__ import annotations

from types import SimpleNamespace

from fastapi.testclient import TestClient
from supabase_auth.errors import AuthApiError

from app.dependencies.ai_services import get_ai_failure_reason_service
from app.dependencies.database import get_auth_database
from app.main import app

from .conftest import USER_ID


class FailureReasonServiceStub:
    def list_active(self):
        return []


class FakeAuth:
    def __init__(self, *, valid: bool, error: Exception | None = None) -> None:
        self.valid = valid
        self.error = error

    def get_user(self, token: str):
        if self.error is not None:
            raise self.error
        if not self.valid:
            raise ValueError("invalid token")
        return SimpleNamespace(user=SimpleNamespace(id=str(USER_ID)))


class FakeDatabase:
    def __init__(self, *, valid: bool, error: Exception | None = None) -> None:
        self.auth = FakeAuth(valid=valid, error=error)


def _override_non_auth_dependencies(*, valid_token: bool) -> None:
    app.dependency_overrides[get_auth_database] = lambda: FakeDatabase(valid=valid_token)
    app.dependency_overrides[get_ai_failure_reason_service] = (
        lambda: FailureReasonServiceStub()
    )


def test_v2_rejects_missing_token(client: TestClient) -> None:
    _override_non_auth_dependencies(valid_token=True)

    response = client.get("/api/v2/ai/failure-reasons")

    assert response.status_code == 401


def test_v2_rejects_spoofed_x_user_id(client: TestClient) -> None:
    _override_non_auth_dependencies(valid_token=True)

    response = client.get(
        "/api/v2/ai/failure-reasons",
        headers={"X-User-Id": str(USER_ID)},
    )

    assert response.status_code == 401


def test_v2_rejects_invalid_token(client: TestClient) -> None:
    _override_non_auth_dependencies(valid_token=False)

    response = client.get(
        "/api/v2/ai/failure-reasons",
        headers={"Authorization": "Bearer invalid"},
    )

    assert response.status_code == 401


def test_v2_accepts_valid_supabase_user(client: TestClient) -> None:
    _override_non_auth_dependencies(valid_token=True)

    response = client.get(
        "/api/v2/ai/failure-reasons",
        headers={"Authorization": "Bearer valid-token"},
    )

    assert response.status_code == 200


def test_v2_maps_auth_server_error_to_service_unavailable(client: TestClient) -> None:
    app.dependency_overrides[get_auth_database] = lambda: FakeDatabase(
        valid=True,
        error=AuthApiError("internal", 500, None),
    )
    app.dependency_overrides[get_ai_failure_reason_service] = (
        lambda: FailureReasonServiceStub()
    )

    response = client.get(
        "/api/v2/ai/failure-reasons",
        headers={"Authorization": "Bearer valid-token"},
    )

    assert response.status_code == 503
