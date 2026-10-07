from __future__ import annotations

from copy import deepcopy
from uuid import UUID, uuid4

import pytest

from app.core.errors import DatabaseUnavailableError, ResourceConflictError
from app.routes import tasks as task_routes
from app.schemas.task import TaskCreate, TaskResponse
from app.services import task_ai_sync_service as sync_module
from app.services.task_ai_sync_service import TaskAISyncService, sync_task_ai_safely

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

TASK_ID = str(uuid4())
PLAN_ID = str(uuid4())


def snapshot(plan_id=PLAN_ID, parent=None):
    return {
        "id": plan_id, "user_id": str(USER_ID), "parent_plan_input_id": parent,
        "title": "Study", "created_at": "2026-10-06T12:00:00+00:00",
        "planned_start": "2026-10-07T15:00:00+00:00",
        "daily_planned_minutes": 60,
    }


def task_row(plan_id=PLAN_ID):
    return {
        "id": TASK_ID, "user_id": str(USER_ID), "title": "Study",
        "task_category": "Study", "planned_start_time": "9:00 AM",
        "planned_date": "2026-10-07", "planned_duration_min": 60,
        "importance": 3, "energy_level": 3, "focus_level": 3,
        "total_tasks_today": 1, "task_status": "pending",
        "created_at": "2026-10-06T12:00:00+00:00", "timezone_name": "America/Denver",
        "ai_plan_input_id": plan_id, "ai_sync_status": "pending",
    }


def job(plan_id=PLAN_ID, parent=None, sequence=1):
    return {
        "id": plan_id, "user_id": str(USER_ID), "task_id": TASK_ID,
        "sequence": sequence, "status": "pending", "payload": snapshot(plan_id, parent),
    }


class Plans:
    def __init__(self):
        self.rows = {}
        self.offline = False
        self.lose_response = False
        self.race = False

    def get_owned(self, plan_id, user_id):
        if self.offline:
            raise DatabaseUnavailableError()
        row = self.rows.get(str(plan_id))
        return row if row and row["user_id"] == str(user_id) else None

    def create(self, payload):
        parent = payload["parent_plan_input_id"]
        assert parent is None or parent in self.rows
        if payload["id"] in self.rows:
            raise ResourceConflictError()
        self.rows[payload["id"]] = deepcopy(payload)
        if self.lose_response:
            self.lose_response = False
            raise DatabaseUnavailableError()
        if self.race:
            self.race = False
            raise ResourceConflictError()
        return payload


def database(jobs=None, task=None):
    return MemoryDatabase({
        "tasks": [task or task_row()], "task_ai_sync_jobs": jobs or [job()],
    })


def test_ai_outage_keeps_job_and_later_retry_preserves_original_snapshot(monkeypatch):
    db, plans = database(), Plans()
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: True)
    monkeypatch.setattr(sync_module, "get_ai_supabase", lambda: object())
    monkeypatch.setattr(sync_module, "AIPlanRepository", lambda _: plans)
    plans.offline = True
    assert sync_task_ai_safely(db, task_row())["ai_sync_status"] == "pending"
    assert db.rows["task_ai_sync_jobs"][0]["status"] == "pending"
    plans.offline = False
    # Delivery time and subsequent context must not replace the captured input.
    db.rows["tasks"][0]["title"] = "Later title"
    saved = sync_task_ai_safely(db, task_row())
    assert saved["ai_sync_status"] == "synced"
    assert plans.rows[PLAN_ID] == snapshot()
    assert TaskAISyncService(db, plans).sync_task(str(USER_ID), TASK_ID)
    assert len(plans.rows) == 1


def test_lost_insert_response_does_not_create_duplicate_on_retry():
    db, plans = database(), Plans()
    plans.lose_response = True
    service = TaskAISyncService(db, plans)
    with pytest.raises(DatabaseUnavailableError):
        service.sync_task(str(USER_ID), TASK_ID)
    assert db.rows["task_ai_sync_jobs"][0]["status"] == "pending"
    assert service.sync_task(str(USER_ID), TASK_ID)
    assert len(plans.rows) == 1


def test_concurrent_delivery_conflict_is_reconciled():
    db, plans = database(), Plans()
    plans.race = True
    assert TaskAISyncService(db, plans).sync_task(str(USER_ID), TASK_ID)
    assert len(plans.rows) == 1


def test_revisions_delivered_parent_first_and_latest_link_is_retained():
    child_id = str(uuid4())
    db = database([job(child_id, PLAN_ID, 2), job()], task_row(child_id))
    plans = Plans()
    assert TaskAISyncService(db, plans).sync_task(str(USER_ID), TASK_ID)
    assert list(plans.rows) == [PLAN_ID, child_id]
    assert db.rows["tasks"][0]["ai_plan_input_id"] == child_id


def test_reconcile_task_after_job_acknowledgment_was_committed():
    synced_job = job()
    synced_job["status"] = "synced"
    db = database([synced_job])
    assert TaskAISyncService(db, Plans()).sync_task(str(USER_ID), TASK_ID)
    assert db.rows["tasks"][0]["ai_sync_status"] == "synced"


def test_edit_during_acknowledgment_cannot_mark_new_revision_synced(monkeypatch):
    db, plans = database(), Plans()
    original_table = db.table
    child_id = str(uuid4())

    def table(name):
        query = original_table(name)
        original_update = query.update

        def update(values):
            if name == "tasks":
                # Another request commits a revision after sync reads the old
                # pointer but before its conditional acknowledgment executes.
                db.rows["tasks"][0]["ai_plan_input_id"] = child_id
                db.rows["task_ai_sync_jobs"].append(job(child_id, PLAN_ID, 2))
            return original_update(values)

        query.update = update
        return query

    monkeypatch.setattr(db, "table", table)
    assert not TaskAISyncService(db, plans).sync_task(str(USER_ID), TASK_ID)
    assert db.rows["tasks"][0]["ai_sync_status"] == "pending"
    assert db.rows["tasks"][0]["ai_plan_input_id"] == child_id
    assert child_id not in plans.rows


def test_other_users_jobs_and_tasks_are_inaccessible():
    db, plans = database(), Plans()
    assert not TaskAISyncService(db, plans).sync_task(str(uuid4()), TASK_ID)
    assert plans.rows == {}
    assert db.rows["task_ai_sync_jobs"][0]["status"] == "pending"


def test_api_hides_pending_link_and_returns_synced_link_on_another_device(
    authenticated_client, monkeypatch,
):
    db = database()
    monkeypatch.setattr(task_routes, "_require_db", lambda: db)
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: False)
    pending = authenticated_client.get(f"/tasks/{TASK_ID}")
    assert pending.status_code == 200
    assert pending.json()["ai_plan_input_id"] is None
    assert pending.json()["ai_sync_status"] == "pending"
    assert authenticated_client.post(f"/tasks/{TASK_ID}/ai-plan", json={}).status_code == 503
    plans = Plans()
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: True)
    monkeypatch.setattr(sync_module, "get_ai_supabase", lambda: object())
    monkeypatch.setattr(sync_module, "AIPlanRepository", lambda _: plans)
    synced = authenticated_client.post(f"/tasks/{TASK_ID}/ai-plan", json={})
    assert synced.status_code == 200
    assert synced.json()["ai_plan_input_id"] == PLAN_ID
    assert authenticated_client.get("/tasks").json()[0]["ai_plan_input_id"] == PLAN_ID


def test_sync_endpoint_rejects_other_users_and_retrospective_inputs(
    authenticated_client, monkeypatch,
):
    db = database()
    monkeypatch.setattr(task_routes, "_require_db", lambda: db)
    assert authenticated_client.post(f"/tasks/{uuid4()}/ai-plan", json={}).status_code == 404
    db.rows["tasks"][0].update({
        "task_status": "success", "ai_plan_input_id": None, "ai_sync_status": "unlinked",
    })
    assert authenticated_client.post(f"/tasks/{TASK_ID}/ai-plan", json={}).status_code == 409


def test_sync_endpoint_requires_auth(client):
    assert client.post(f"/tasks/{TASK_ID}/ai-plan", json={}).status_code == 401


@pytest.mark.parametrize("bad", [
    {"planned_start_time": "25:30"}, {"planned_date": "2026-02-30"},
    {"timezone_name": "not/a/timezone"},
])
def test_task_planning_inputs_are_validated(bad):
    payload = {key: value for key, value in task_row().items() if key in TaskCreate.model_fields}
    with pytest.raises(ValueError):
        TaskCreate.model_validate({**payload, **bad})


def test_pending_snapshot_id_is_not_exposed_to_prediction_clients():
    assert TaskResponse.model_validate(task_row()).ai_plan_input_id is None
    assert UUID(PLAN_ID)
