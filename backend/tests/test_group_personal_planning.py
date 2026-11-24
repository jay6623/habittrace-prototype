"""Private group previews must not persist, disclose teammates' data, or duplicate plans."""

from copy import deepcopy
from datetime import datetime, timezone
from typing import cast
from unittest.mock import Mock
from zoneinfo import ZoneInfo

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
    database.unique_keys["tasks"] = [("user_id", "source_group_task_id", "group_block_key")]
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


CONTEXT = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/personal-plans"
ACK = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/acknowledge-source"
SHARE = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/linked-completion"
PROGRESS = f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}/progress"
SECOND_KEY = "11111111-2222-4333-8444-555555555555"


def test_alternatives_span_days_and_check_future_calendar(authenticated_client, setup):
    database, _, _, calendar = setup
    database.rows["group_tasks"][0]["due_date"] = "2099-09-09"
    calendar.list_busy_events.return_value = [
        {
            "start": "2099-09-07T06:00:00Z",
            "end": "2099-09-08T06:00:00Z",
            "title": "All day",
        }
    ]
    body = authenticated_client.post(PREVIEW, json=BODY).json()
    assert body["search_start"] == "2099-09-06"
    assert body["search_end"] == "2099-09-09"
    assert len(body["candidates"]) == 3
    dates = {
        datetime.fromisoformat(c["planned_start"])
        .astimezone(ZoneInfo("America/Denver"))
        .date()
        .isoformat()
        for c in body["candidates"]
    }
    assert dates == {"2099-09-06", "2099-09-08", "2099-09-09"}
    assert all(c["daily_planned_minutes"] == 60 for c in body["candidates"])
    assert all(c["deadline_slack_minutes"] >= 0 for c in body["candidates"])
    _, start, end = calendar.list_busy_events.call_args.args
    assert start.date().isoformat() == "2099-09-06"
    assert end.date().isoformat() == "2099-09-10"


def test_search_is_bounded_even_without_deadline_and_model(authenticated_client, setup):
    database, _, model, _ = setup
    database.rows["group_tasks"][0]["due_date"] = None
    model.is_ready = False
    response = authenticated_client.post(PREVIEW, json={**BODY, "search_days": 7})
    assert response.status_code == 200
    body = response.json()
    assert body["search_end"] == "2099-09-12"
    assert len(body["candidates"]) == 3
    assert all(c["success_probability"] is None for c in body["candidates"])
    assert authenticated_client.post(PREVIEW, json={**BODY, "search_days": 32}).status_code == 422


def test_split_blocks_are_independently_idempotent_and_private(authenticated_client, setup):
    database, _, _, _ = setup
    database.rows["group_tasks"][0]["estimated_duration_minutes"] = 120
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    second_input = {**BODY, "block_key": SECOND_KEY, "planned_start": "2099-09-06T18:00:00Z"}
    second = authenticated_client.post(CONFIRM, json=second_input).json()
    retry = authenticated_client.post(CONFIRM, json=second_input).json()
    assert first["id"] != second["id"] == retry["id"]
    assert len(database.rows["tasks"]) == 2
    context = authenticated_client.get(CONTEXT).json()
    assert context["planned_minutes"] == 120
    assert context["remaining_minutes"] == 0
    assert len(context["blocks"]) == 2
    assert not any(b["source_changed"] for b in context["blocks"])
    shared = authenticated_client.get(f"/groups/{OWN_GROUP_ID}").json()
    assert "group_block_key" not in str(shared)
    assert "group_source_snapshot" not in str(shared)


def test_pending_block_can_be_rescored_and_moved_without_self_conflict(authenticated_client, setup):
    database, _, _, _ = setup
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    edit = {**BODY, "personal_task_id": first["id"]}
    preview = authenticated_client.post(PREVIEW, json=edit)
    assert preview.status_code == 200, preview.text
    assert preview.json()["prediction"]
    assert preview.json()["conflicts"] == []
    moved = authenticated_client.post(
        CONFIRM, json={**edit, "planned_start": "2099-09-06T18:00:00Z"}
    )
    assert moved.status_code == 200, moved.text
    assert moved.json()["id"] == first["id"]
    assert moved.json()["planned_start_time"] == "12:00"
    assert len(database.rows["tasks"]) == 1


def test_reschedule_cannot_edit_recorded_running_or_other_users_block(authenticated_client, setup):
    database, _, _, _ = setup
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    edit = {**BODY, "personal_task_id": first["id"]}
    database.rows["tasks"][0]["task_status"] = "success"
    assert authenticated_client.post(CONFIRM, json=edit).status_code == 409
    database.rows["tasks"][0]["task_status"] = "pending"
    database.rows["executions"] = [
        {"task_id": first["id"], "user_id": str(USER_ID), "task_status": None}
    ]
    assert authenticated_client.post(PREVIEW, json=edit).status_code == 409
    database.rows["executions"] = []
    database.rows["tasks"][0]["user_id"] = OTHER_ID
    assert authenticated_client.post(CONFIRM, json=edit).status_code == 404


def test_move_rechecks_other_blocks_and_new_deadline(authenticated_client, setup):
    database, _, _, _ = setup
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    database.rows["tasks"].append(personal_task(planned_start_time="12:00"))
    edit = {**BODY, "personal_task_id": first["id"], "planned_start": "2099-09-06T18:00:00Z"}
    assert authenticated_client.post(CONFIRM, json=edit).status_code == 409
    database.rows["tasks"].pop()
    database.rows["group_tasks"][0]["due_time"] = "11:00:00"
    assert authenticated_client.post(CONFIRM, json=edit).status_code == 422


def test_source_change_requires_review_and_preserves_schedule(authenticated_client, setup):
    database, _, _, _ = setup
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    source = database.rows["group_tasks"][0]
    source["due_time"] = "09:00:00"
    context = authenticated_client.get(CONTEXT)
    assert context.headers["cache-control"] == "no-store"
    assert context.json()["blocks"][0]["source_changed"]
    assert context.json()["blocks"][0]["finishes_after_deadline"]
    assert len(authenticated_client.get("/groups/personal-review").json()) == 1
    assert database.rows["tasks"][0]["planned_start_time"] == first["planned_start_time"]
    assert (
        authenticated_client.post(
            ACK, json={"expected_source_updated_at": source["updated_at"]}
        ).status_code
        == 409
    )
    source["due_time"] = "20:00:00"
    assert (
        authenticated_client.post(ACK, json={"expected_source_updated_at": "stale"}).status_code
        == 409
    )
    acknowledged = authenticated_client.post(
        ACK, json={"expected_source_updated_at": source["updated_at"]}
    )
    assert acknowledged.status_code == 200
    assert not acknowledged.json()["blocks"][0]["source_changed"]
    assert authenticated_client.get("/groups/personal-review").json() == []


def test_new_source_version_rejects_stale_confirmation(authenticated_client, setup):
    assert (
        authenticated_client.post(
            CONFIRM, json={**BODY, "expected_source_updated_at": "old"}
        ).status_code
        == 409
    )
    database, _, _, _ = setup
    assert not database.rows.get("tasks")


def test_completed_blocks_offer_explicit_retryable_shared_completion(authenticated_client, setup):
    database, _, _, _ = setup
    database.rows["group_tasks"][0]["estimated_duration_minutes"] = 60
    authenticated_client.post(CONFIRM, json=BODY)
    assert authenticated_client.post(SHARE, json={"confirmed": True}).status_code == 409
    database.rows["tasks"][0]["task_status"] = "success"
    before = deepcopy(database.rows["tasks"])
    assert authenticated_client.get(CONTEXT).json()["can_share_completion"]
    assert database.rows["group_task_assignees"][-1].get("outcome") is None
    assert authenticated_client.post(SHARE, json={"confirmed": False}).status_code == 422
    for _ in range(2):
        result = authenticated_client.post(SHARE, json={"confirmed": True})
        assert result.status_code == 200, result.text
        assert result.json()["shared_outcome"] == "success"
    assert database.rows["tasks"] == before
    assert not database.rows.get("executions")  # No duplicate result or XP source.
    assert authenticated_client.get("/groups/personal-review").json() == []


def test_one_short_completed_block_does_not_complete_long_group_work(authenticated_client, setup):
    database, _, _, _ = setup
    database.rows["group_tasks"][0]["estimated_duration_minutes"] = 180
    authenticated_client.post(CONFIRM, json=BODY)
    database.rows["tasks"][0]["task_status"] = "success"
    assert not authenticated_client.get(CONTEXT).json()["can_share_completion"]
    assert authenticated_client.post(SHARE, json={"confirmed": True}).status_code == 409


def test_progress_is_opt_in_self_only_and_can_be_cleared(authenticated_client, setup):
    database, _, _, _ = setup
    shared = authenticated_client.get(f"/groups/{OWN_GROUP_ID}").json()
    assert all(a["shared_progress"] is None for a in shared["tasks"][0]["assignees"])
    for value in ["planned", "in_progress", "needs_help", None]:
        result = authenticated_client.patch(PROGRESS, json={"shared_progress": value})
        assert result.status_code == 200, result.text
        mine = next(a for a in result.json()["assignees"] if a["user_id"] == str(USER_ID))
        assert mine["shared_progress"] == value
        assert database.rows["group_task_assignees"][0].get("shared_progress") is None
    assert (
        authenticated_client.patch(
            PROGRESS, json={"shared_progress": "private", "user_id": OTHER_ID}
        ).status_code
        == 422
    )


@pytest.mark.parametrize(
    "method,path,body",
    [
        ("get", CONTEXT, None),
        ("get", "/groups/personal-review", None),
        ("post", ACK, {"expected_source_updated_at": "v"}),
        ("post", SHARE, {"confirmed": True}),
        ("patch", PROGRESS, {"shared_progress": "planned"}),
    ],
)
def test_new_routes_require_auth(client, setup, method, path, body):
    app.dependency_overrides[get_auth_database] = lambda: object()
    assert client.request(method, path, json=body).status_code == 401


@pytest.mark.parametrize(
    "method,path,body",
    [
        ("get", CONTEXT, None),
        ("post", ACK, {"expected_source_updated_at": "v"}),
        ("post", SHARE, {"confirmed": True}),
        ("patch", PROGRESS, {"shared_progress": "planned"}),
    ],
)
def test_removed_member_cannot_read_or_publish_linked_work(
    authenticated_client, setup, method, path, body
):
    database, _, _, _ = setup
    authenticated_client.post(CONFIRM, json=BODY)
    database.rows["group_members"] = [
        r for r in database.rows["group_members"] if r["user_id"] != str(USER_ID)
    ]
    assert authenticated_client.request(method, path, json=body).status_code == 404
    assert authenticated_client.get("/groups/personal-review").json() == []


def test_daily_load_clips_overnight_work_and_merges_busy_overlap(authenticated_client, setup):
    database, _, _, calendar = setup
    database.rows["tasks"] = [
        personal_task(
            planned_date="2099-09-05", planned_start_time="23:30", planned_duration_min=120
        )
    ]
    calendar.list_busy_events.return_value = [
        {"start": "2099-09-06T06:00:00Z", "end": "2099-09-06T08:00:00Z", "title": "Busy"}
    ]
    response = authenticated_client.post(PREVIEW, json=BODY)
    assert response.status_code == 200, response.text
    # Midnight–02:00 busy union (120 min), plus proposed 60 min; no double counting.
    assert all(c["daily_planned_minutes"] == 180 for c in response.json()["candidates"])


def test_acknowledging_deadline_updates_pending_ai_context_not_completed_history(
    authenticated_client, setup
):
    database, _, _, _ = setup
    authenticated_client.post(CONFIRM, json=BODY)
    pending = database.rows["tasks"][0]
    completed = personal_task(
        id="11111111-1111-4111-8111-111111111111",
        task_status="success",
        source_group_task_id=OWN_TASK_ID,
        ai_plan_details={"deadline_at": "historical"},
    )
    database.rows["tasks"].append(completed)
    source = database.rows["group_tasks"][0]
    source["due_time"] = "20:00:00"
    result = authenticated_client.post(
        ACK, json={"expected_source_updated_at": source["updated_at"]}
    )
    assert result.status_code == 200, result.text
    assert pending["ai_plan_details"]["current_energy"] == 2
    assert pending["ai_plan_details"]["deadline_at"] == "2099-09-07T02:00:00+00:00"
    assert completed["ai_plan_details"]["deadline_at"] == "historical"


def test_sharing_completion_does_not_change_gamification_xp(authenticated_client, setup):
    from datetime import date

    from app.repositories.gamification_repository import GamificationRepository
    from app.services.gamification_service import GamificationService

    database, _, _, _ = setup
    row = authenticated_client.post(CONFIRM, json=BODY).json()
    database.rows["tasks"][0]["task_status"] = "success"
    database.rows["executions"] = [
        {
            "id": "result-1",
            "task_id": row["id"],
            "user_id": str(USER_ID),
            "task_status": "success",
            "outcome_status": "completed",
            "completion_ratio": 1,
            "created_at": "2099-09-06T18:00:00Z",
        }
    ]
    service = GamificationService(GamificationRepository(cast(Client, database)))
    before = service.get_summary(USER_ID, date(2099, 9, 6))
    assert before["plan_xp"] > 0
    assert authenticated_client.post(SHARE, json={"confirmed": True}).status_code == 200
    after = service.get_summary(USER_ID, date(2099, 9, 6))
    assert after == before
    assert len(database.rows["executions"]) == 1


def test_concurrent_outcome_is_not_overwritten_by_rescheduling(
    authenticated_client, setup, monkeypatch
):
    database, service, _, _ = setup
    first = authenticated_client.post(CONFIRM, json=BODY).json()
    update = service.tasks.update

    def recorded_before_update(user_id, task_id, payload, **kwargs):
        database.rows["tasks"][0]["task_status"] = "success"
        return update(user_id, task_id, payload, **kwargs)

    monkeypatch.setattr(service.tasks, "update", recorded_before_update)
    result = authenticated_client.post(
        CONFIRM,
        json={**BODY, "personal_task_id": first["id"], "planned_start": "2099-09-06T18:00:00Z"},
    )
    assert result.status_code == 409
    assert database.rows["tasks"][0]["task_status"] == "success"
    assert database.rows["tasks"][0]["planned_start_time"] == first["planned_start_time"]
