"""Private group previews must not persist, disclose teammates' data, or duplicate plans."""

from copy import deepcopy
from datetime import datetime, timezone
from typing import cast
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from supabase import Client

from app.dependencies.database import get_auth_database
from app.main import app
from app.rate_limit import rate_limiter
from app.repositories.group_repository import GroupRepository
from app.repositories.personalization_repository import PersonalizationRepository
from app.routes.groups import get_group_personal_planning_service
from app.services.group_personal_planning_service import GroupPersonalPlanningService
from app.services.group_service import GroupService
from app.services.personalization_service import PersonalizationService
from app.services.task_service import TaskService

from .conftest import USER_ID
from .test_groups_api import (
    FOREIGN_GROUP_ID,
    FOREIGN_TASK_ID,
    OTHER_ID,
    OWN_GROUP_ID,
    OWN_TASK_ID,
    _use_memory_database,
)

BODY = {
    "planned_start": "2099-09-06T16:00:00Z",
    "planned_duration_minutes": 60,
    "timezone_name": "America/Denver",
    "current_energy": 2,
    "current_focus": 4,
    "required_energy": 4,
    "required_focus": 3,
}
PREVIEW = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/personal-preview"
CONFIRM = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/personal-plan"


@pytest.fixture
def setup(monkeypatch):
    database = _use_memory_database()
    database.unique_keys["tasks"] = [("user_id", "source_group_task_id")]
    database.rows["group_tasks"][0].update(
        due_date="2099-09-06",
        due_time="22:00:00",
        due_timezone_name="America/Denver",
    )
    database.rows["group_task_assignees"].append(
        {
            "group_id": OWN_GROUP_ID,
            "task_id": OWN_TASK_ID,
            "user_id": str(USER_ID),
        }
    )
    db = cast(Client, database)
    model = Mock(is_ready=True)
    model.predict.side_effect = lambda _plan: {
        "model_version": "test",
        "success_probability": 0.7,
        "failure_reason_probabilities": {"interruption": 0.3},
        "predicted_failure_reason": "interruption",
        "predicted_at": datetime.now(timezone.utc),
        "explanation": {"notice": "experimental"},
        "recommended_actions": [],
    }
    calendar = Mock()
    calendar.list_busy_events.return_value = []
    personalization = PersonalizationService(PersonalizationRepository(db))
    service = GroupPersonalPlanningService(
        GroupService(GroupRepository(db)),
        TaskService(db),
        model,
        personalization,
        calendar,
    )
    app.dependency_overrides[get_group_personal_planning_service] = lambda: service
    rate_limiter._events.clear()
    monkeypatch.setattr("app.services.task_service.sync_task_ai_safely", lambda _db, task: task)
    return database, service, model, calendar


def personal_task(**values):
    return {
        "id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
        "user_id": str(USER_ID),
        "title": "Private work",
        "planned_start_time": "10:00",
        "planned_date": "2099-09-06",
        "planned_duration_min": 60,
        "task_category": "Work",
        "importance": 3,
        "energy_level": 3,
        "focus_level": 3,
        "total_tasks_today": 1,
        "task_status": "pending",
        "created_at": "2026-09-01T12:00:00Z",
        "timezone_name": "America/Denver",
        **values,
    }


@pytest.mark.parametrize("path", [PREVIEW, CONFIRM])
def test_requires_auth(client: TestClient, setup, path):
    app.dependency_overrides[get_auth_database] = lambda: object()
    assert client.post(path, json=BODY).status_code == 401


@pytest.mark.parametrize("suffix", ["personal-preview", "personal-plan"])
def test_nonmembers_and_cross_group_tasks_are_hidden(authenticated_client, setup, suffix):
    for group, task in [(FOREIGN_GROUP_ID, FOREIGN_TASK_ID), (OWN_GROUP_ID, FOREIGN_TASK_ID)]:
        response = authenticated_client.post(f"/groups/{group}/tasks/{task}/{suffix}", json=BODY)
        assert response.status_code == 404


@pytest.mark.parametrize("path", [PREVIEW, CONFIRM])
def test_owner_cannot_predict_for_unassigned_self(authenticated_client, setup, path):
    database, _, model, _ = setup
    database.rows["group_task_assignees"] = database.rows["group_task_assignees"][:1]
    assert authenticated_client.post(path, json=BODY).status_code == 403
    model.predict.assert_not_called()


def test_preview_is_private_read_only_and_uses_own_history(authenticated_client, setup):
    database, service, _, _ = setup
    database.rows["tasks"] = [personal_task(user_id=OTHER_ID, title="Teammate secret")]
    before = deepcopy(database.rows)
    history = Mock(wraps=service.personalization.history.list_completed_tasks)
    service.personalization.history.list_completed_tasks = history
    response = authenticated_client.post(PREVIEW, json=BODY)
    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "no-store"
    body = response.json()
    assert body["prediction"]["success_probability"] == 0.7
    assert body["prediction"]["explanation"]["notice"] == "experimental"
    assert body["conflicts"] == []
    assert len(body["candidates"]) == 3
    assert "Teammate secret" not in response.text
    history.assert_called_once_with(USER_ID)
    assert database.rows == {**before, "tasks": before["tasks"]}


def test_detects_conflict_and_rechecks_on_confirmation(authenticated_client, setup):
    database, _, _, _ = setup
    preview = authenticated_client.post(PREVIEW, json=BODY)
    assert preview.json()["conflicts"] == []
    database.rows["tasks"] = [personal_task()]
    assert authenticated_client.post(CONFIRM, json=BODY).status_code == 409
    preview = authenticated_client.post(PREVIEW, json=BODY).json()
    assert preview["conflicts"] == ["Private work"]
    assert all(c["planned_start"] != BODY["planned_start"] for c in preview["candidates"])


def test_cross_midnight_personal_plan_blocks_next_day(authenticated_client, setup):
    database, _, _, _ = setup
    database.rows["tasks"] = [
        personal_task(
            planned_date="2099-09-05",
            planned_start_time="23:30",
            planned_duration_min=120,
        )
    ]
    body = {**BODY, "planned_start": "2099-09-06T06:30:00Z"}
    assert authenticated_client.post(CONFIRM, json=body).status_code == 409


@pytest.mark.parametrize(
    "body",
    [
        {**BODY, "planned_start": "2020-01-01T16:00:00Z"},
        {**BODY, "planned_start": "2099-09-07T03:30:00Z"},
        {**BODY, "planned_start": "2099-09-06T16:00:00"},
        {**BODY, "planned_duration_minutes": 721},
        {**BODY, "timezone_name": "Invalid/Timezone"},
        {**BODY, "user_id": OTHER_ID},
        {**BODY, "current_energy": 0},
        {**BODY, "planned_start": "2099-09-06T16:00:30Z"},
    ],
)
def test_rejects_invalid_private_inputs(authenticated_client, setup, body):
    assert authenticated_client.post(PREVIEW, json=body).status_code == 422
    assert authenticated_client.post(CONFIRM, json=body).status_code == 422


def test_confirm_creates_one_linked_owned_plan_and_preserves_shared_task(
    authenticated_client,
    setup,
):
    database, _, _, calendar = setup
    before = deepcopy(database.rows["group_tasks"])
    first = authenticated_client.post(CONFIRM, json=BODY)
    second = authenticated_client.post(CONFIRM, json=BODY)
    assert first.status_code == second.status_code == 200, first.text
    assert first.json()["id"] == second.json()["id"]
    assert first.json()["source_group_task_id"] == OWN_TASK_ID
    assert first.json()["user_id"] == str(USER_ID)
    assert first.json()["planned_start_time"] == "10:00"
    assert first.json()["planned_date"] == "2099-09-06"
    assert first.json()["energy_level"] == 4
    assert database.rows["tasks"][0]["ai_plan_details"]["current_energy"] == 2
    assert database.rows["group_tasks"] == before
    assert len(database.rows["tasks"]) == 1
    calendar.sync_task_safely.assert_called_once()
    preview = authenticated_client.post(PREVIEW, json=BODY).json()
    assert preview["personal_task"]["id"] == first.json()["id"]
    shared = authenticated_client.get(f"/groups/{OWN_GROUP_ID}").json()
    assert "source_group_task_id" not in str(shared)
    assert "prediction" not in str(shared)


def test_model_unavailable_still_allows_explicit_confirmation(authenticated_client, setup):
    _, _, model, _ = setup
    model.is_ready = False
    preview = authenticated_client.post(PREVIEW, json=BODY).json()
    assert preview["prediction"] is None
    assert preview["warnings"]
    assert authenticated_client.post(CONFIRM, json=BODY).status_code == 200


def test_calendar_conflicts_and_outage_warning(authenticated_client, setup):
    _, _, _, calendar = setup
    calendar.list_busy_events.return_value = [
        {
            "start": "2099-09-06T16:00:00Z",
            "end": "2099-09-06T17:00:00Z",
            "title": "Meeting",
        }
    ]
    assert authenticated_client.post(PREVIEW, json=BODY).json()["conflicts"] == ["Meeting"]
    assert authenticated_client.post(CONFIRM, json=BODY).status_code == 409
    calendar.list_busy_events.side_effect = RuntimeError("offline")
    preview = authenticated_client.post(PREVIEW, json=BODY).json()
    assert any("Google Calendar" in warning for warning in preview["warnings"])


def test_group_duration_contract(authenticated_client, setup):
    response = authenticated_client.post(
        f"/groups/{OWN_GROUP_ID}/tasks",
        json={
            "title": "Study together",
            "estimated_duration_minutes": 45,
            "due_timezone_name": "America/Denver",
        },
    )
    assert response.status_code == 201
    assert response.json()["estimated_duration_minutes"] == 45
    assert (
        authenticated_client.post(
            f"/groups/{OWN_GROUP_ID}/tasks",
            json={
                "title": "Invalid",
                "estimated_duration_minutes": 0,
            },
        ).status_code
        == 422
    )


def test_confirmation_race_returns_the_original_plan(authenticated_client, setup, monkeypatch):
    database, service, _, _ = setup
    create = service.tasks.create

    def concurrent_create(user_id, payload):
        create(user_id, payload)
        return create(user_id, payload)

    monkeypatch.setattr(service.tasks, "create", concurrent_create)
    response = authenticated_client.post(CONFIRM, json=BODY)
    assert response.status_code == 200, response.text
    assert len(database.rows["tasks"]) == 1
    assert response.json()["id"] == database.rows["tasks"][0]["id"]


def test_date_only_deadline_means_end_of_day(authenticated_client, setup):
    database, _, _, _ = setup
    database.rows["group_tasks"][0]["due_time"] = None
    response = authenticated_client.post(
        PREVIEW,
        json={
            **BODY,
            "planned_start": "2099-09-07T05:30:00Z",
        },
    )
    assert response.status_code == 422


def test_removed_members_cannot_reopen_private_preview(authenticated_client, setup):
    database, _, _, _ = setup
    assert authenticated_client.post(CONFIRM, json=BODY).status_code == 200
    database.rows["group_members"] = [
        row for row in database.rows["group_members"] if row["user_id"] != str(USER_ID)
    ]
    assert authenticated_client.post(PREVIEW, json=BODY).status_code == 404
    assert len(database.rows["tasks"]) == 1


def test_real_model_accepts_group_plan_features(authenticated_client, setup):
    from app.services.ai_v2_ml_service import get_ai_v2_ml_service

    _, service, _, _ = setup
    service.model = get_ai_v2_ml_service()
    assert service.model.is_ready
    response = authenticated_client.post(PREVIEW, json=BODY)
    assert response.status_code == 200, response.text
    prediction = response.json()["prediction"]
    assert prediction is not None
    assert 0 <= prediction["success_probability"] <= 1
    assert prediction["explanation"]["notice"]
