"""Calendar schedule edits through the real HTTP routes, using an isolated DB."""
from copy import deepcopy

import pytest

from app.routes import tasks as task_routes
from app.services import task_ai_sync_service as sync_module
from app.services.google_calendar_service import GoogleCalendarService

from .test_task_ai_sync import TASK_ID, database, task_row


@pytest.mark.parametrize("status", ["pending", "success", "failed"])
def test_calendar_patch_survives_fresh_reads_and_moves_between_dates(
    authenticated_client, monkeypatch, status,
):
    original = task_row()
    original.update(task_status=status, energy_level=2, focus_level=5)
    db = database(task=original)
    monkeypatch.setattr(task_routes, "_require_db", lambda: db)
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: False)
    monkeypatch.setattr(GoogleCalendarService, "sync_task_safely", lambda *args: None)
    changes = {
        "title": "Calendar edited plan", "planned_date": "2026-11-30",
        "planned_start_time": "11:45 PM",
    }
    response = authenticated_client.patch(f"/tasks/{TASK_ID}", json=changes)
    assert response.status_code == 200
    # New HTTP reads simulate the requests made after navigation or reload.
    saved = authenticated_client.get(f"/tasks/{TASK_ID}").json()
    assert all(saved[key] == value for key, value in changes.items())
    assert saved["task_status"] == status
    assert saved["energy_level"] == 2
    assert saved["focus_level"] == 5
    assert authenticated_client.get("/tasks?date=2026-10-07").json() == []
    assert authenticated_client.get("/tasks?date=2026-11-30").json()[0]["id"] == TASK_ID


def test_invalid_calendar_edit_keeps_existing_record(authenticated_client, monkeypatch):
    db = database()
    before = deepcopy(db.rows["tasks"])
    monkeypatch.setattr(task_routes, "_require_db", lambda: db)
    response = authenticated_client.patch(f"/tasks/{TASK_ID}", json={
        "title": "Do not apply", "planned_date": "invalid", "planned_start_time": "25:00",
    })
    assert response.status_code == 422
    assert db.rows["tasks"] == before
