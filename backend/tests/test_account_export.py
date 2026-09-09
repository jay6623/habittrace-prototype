from app.routes import account

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase


def test_export_paginates_and_scopes_to_authenticated_owner(authenticated_client, monkeypatch):
    own = [{"id": f"{n:04}", "user_id": str(USER_ID)} for n in range(1001)]
    db = MemoryDatabase({"tasks": own + [{"id": "private", "user_id": "other"}], "executions": []})
    monkeypatch.setattr(account, "is_supabase_configured", lambda: True)
    monkeypatch.setattr(account, "get_supabase", lambda: db)
    response = authenticated_client.get("/account/export")
    assert response.status_code == 200
    assert len(response.json()["tasks"]) == 1001
    assert all(row["user_id"] == str(USER_ID) for row in response.json()["tasks"])


def test_export_does_not_return_partial_data(authenticated_client, monkeypatch):
    monkeypatch.setattr(account, "is_supabase_configured", lambda: True)
    monkeypatch.setattr(account, "get_supabase", lambda: object())
    response = authenticated_client.get("/account/export")
    assert response.status_code == 503
    assert "tasks" not in response.json()
