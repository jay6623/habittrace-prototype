from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import app
from app.routes.google_calendar import get_google_calendar_service
from app.services.google_calendar_service import GoogleCalendarService


class StubCalendarService:
    def __init__(self) -> None:
        self.connected_user: str | None = None
        self.disconnected_user: str | None = None
        self.provider_token: str | None = None

    def status(self, user_id: str) -> dict:
        return {
            "configured": True,
            "connected": user_id == self.connected_user,
            "timezone": "America/Denver" if user_id == self.connected_user else None,
            "last_synced_at": None,
            "last_error": None,
        }

    def connect(
        self,
        user_id: str,
        provider_token: str,
        provider_refresh_token: str | None,
        timezone: str,
    ) -> dict:
        assert provider_refresh_token == "provider-refresh-token"
        assert timezone == "America/Denver"
        self.connected_user = user_id
        self.provider_token = provider_token
        return {}

    def sync_all(self, user_id: str) -> dict:
        assert user_id == self.connected_user
        return {"synced": 2, "failed": 0, "errors": []}

    def disconnect(self, user_id: str) -> None:
        self.disconnected_user = user_id
        self.connected_user = None


def test_calendar_routes_require_authentication(client: TestClient) -> None:
    response = client.get("/integrations/google-calendar/status")
    assert response.status_code == 401


def test_connect_status_sync_and_disconnect_are_user_scoped(
    authenticated_client: TestClient,
) -> None:
    service = StubCalendarService()
    app.dependency_overrides[get_google_calendar_service] = lambda: service

    connected = authenticated_client.post(
        "/integrations/google-calendar/connect",
        json={
            "provider_token": "provider-access-token",
            "provider_refresh_token": "provider-refresh-token",
            "timezone": "America/Denver",
        },
    )
    status = authenticated_client.get("/integrations/google-calendar/status")
    synced = authenticated_client.post("/integrations/google-calendar/sync")
    disconnected = authenticated_client.delete("/integrations/google-calendar")

    assert connected.status_code == 200
    assert connected.json()["sync"]["synced"] == 2
    assert status.json()["connected"] is True
    assert synced.json() == {"synced": 2, "failed": 0, "errors": []}
    assert disconnected.status_code == 204
    assert service.provider_token == "provider-access-token"
    assert service.disconnected_user is not None


def test_tokens_are_encrypted_and_task_times_become_calendar_events() -> None:
    calendar = GoogleCalendarService(
        object(),  # type: ignore[arg-type]
        Settings(
            google_oauth_client_id="client-id",
            google_oauth_client_secret="client-secret",
            google_token_encryption_key="x" * 48,
        ),
    )

    encrypted = calendar._encrypt("sensitive-token")
    event = calendar._event_from_task(
        {
            "id": "task-1",
            "user_id": "user-1",
            "title": "Study",
            "planned_date": "2026-09-03",
            "planned_start_time": "2:30 PM",
            "planned_duration_min": 45,
        },
        "America/Denver",
    )

    assert encrypted != "sensitive-token"
    assert calendar._decrypt(encrypted) == "sensitive-token"
    assert event["start"] == {
        "dateTime": "2026-09-03T14:30:00",
        "timeZone": "America/Denver",
    }
    assert event["end"]["dateTime"] == "2026-09-03T15:15:00"
