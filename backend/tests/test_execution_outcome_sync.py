from __future__ import annotations

from copy import deepcopy
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from pydantic import ValidationError

from app.routes import executions
from app.schemas.execution import ExecutionComplete, ExecutionCreate
from app.services import execution_ai_sync_service as sync_module
from app.services.execution_ai_sync_service import ExecutionAISyncService, sync_execution_ai_safely

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

TASK_ID, EXECUTION_ID, PLAN_ID, JOB_ID = [str(uuid4()) for _ in range(4)]


def outcome(**changes):
    return {
        "task_id": TASK_ID, "task_status": "failed", "outcome_status": "partial",
        "completion_ratio": .35, "interruption_count": 3, "stopped_early": True,
        "failure_reason": "interruption", "actual_start_time": "2026-09-05T10:00:00+00:00",
        "actual_end_time": "2026-09-05T11:00:00+00:00", **changes,
    }


def row(**changes):
    return {
        **outcome(), "id": EXECUTION_ID, "user_id": str(USER_ID),
        "ai_outcome_job_id": JOB_ID, "ai_outcome_sync_status": "pending",
        "created_at": "2026-09-05T12:00:00+00:00", **changes,
    }


def database():
    return MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [row()],
        "execution_ai_sync_jobs": [{
            "id": JOB_ID, "execution_id": EXECUTION_ID, "user_id": str(USER_ID),
            "task_id": TASK_ID, "plan_input_id": PLAN_ID, "sequence": 7,
            "payload": {"completion_ratio": .35, "interruption_count": 3,
                        "learning_eligible": True, "recorded_at": "2026-09-05T12:00:00+00:00"},
            "primary_reason_code": "interruption", "status": "pending",
        }],
    })


class AI:
    def __init__(self):
        self.calls = []
        self.offline = False
        self.lose_response = False
        self.delivered = {}

    def rpc(self, name, payload):
        assert name == "deliver_execution_outcome"

        def execute():
            if self.offline:
                raise httpx.ConnectError("test outage")
            self.calls.append(deepcopy(payload))
            self.delivered[payload["p_execution_id"]] = deepcopy(payload)
            if self.lose_response:
                self.lose_response = False
                raise httpx.ReadError("lost response after commit")
            return SimpleNamespace(data=str(uuid4()))

        return SimpleNamespace(execute=execute)


@pytest.fixture
def plans_ready(monkeypatch):
    calls = []

    class PlanSync:
        def __init__(self, *_args):
            pass

        def sync_task(self, user_id, task_id):
            calls.append((user_id, task_id))
            return True

    monkeypatch.setattr(sync_module, "TaskAISyncService", PlanSync)
    return calls


def test_partial_progress_and_interruptions_are_preserved():
    parsed = ExecutionCreate.model_validate(outcome())
    assert float(parsed.completion_ratio) == .35
    assert parsed.interruption_count == 3
    assert parsed.active_minutes is None


@pytest.mark.parametrize("changes", [
    {"completion_ratio": None}, {"completion_ratio": 0}, {"completion_ratio": 1},
    {"interruption_count": -1}, {"interruption_count": 1.5},
    {"actual_end_time": "2026-09-05T09:00:00+00:00"},
    {"actual_start_time": "2026-09-05T10:00:00"}, {"active_minutes": 61},
    {"failure_reason": "invented"},
])
def test_invalid_outcome_measurements_are_rejected(changes):
    with pytest.raises(ValidationError):
        ExecutionCreate.model_validate(outcome(**changes))


def test_not_started_is_explicit_and_contains_no_fake_execution_times():
    parsed = ExecutionCreate.model_validate({
        "task_id": TASK_ID, "task_status": "failed", "outcome_status": "not_started",
    })
    assert parsed.actual_start_time is None and parsed.actual_end_time is None
    assert parsed.completion_ratio == 0 and parsed.active_minutes == 0
    assert parsed.failure_reason is None
    with pytest.raises(ValidationError):
        ExecutionCreate.model_validate(outcome(outcome_status="not_started", completion_ratio=0))


def test_legacy_failure_does_not_invent_completion_progress():
    parsed = ExecutionComplete(task_status="failed", failure_reason="other")
    assert parsed.outcome_status is None and parsed.completion_ratio is None


def test_outage_then_retry_delivers_same_snapshot_and_reason_atomically(monkeypatch, plans_ready):
    db, ai = database(), AI()
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: True)
    monkeypatch.setattr(sync_module, "get_ai_supabase", lambda: ai)
    ai.offline = True
    assert sync_execution_ai_safely(db, row())["ai_outcome_sync_status"] == "pending"
    assert db.rows["execution_ai_sync_jobs"][0]["status"] == "pending"
    ai.offline = False
    result = sync_execution_ai_safely(db, row())
    assert result["ai_outcome_sync_status"] == "synced"
    assert ai.calls[0]["p_outcome"]["completion_ratio"] == .35
    assert ai.calls[0]["p_primary_reason"] == "interruption"
    assert ai.calls[0]["p_revision"] == 7
    assert ai.calls[0]["p_plan_input_id"] == PLAN_ID
    assert plans_ready == [(str(USER_ID), TASK_ID), (str(USER_ID), TASK_ID)]


def test_lost_delivery_response_is_retried_without_losing_reason(plans_ready):
    db, ai = database(), AI()
    service = ExecutionAISyncService(db, ai)
    ai.lose_response = True
    with pytest.raises(httpx.ReadError):
        service.sync_execution(str(USER_ID), EXECUTION_ID)
    assert db.rows["execution_ai_sync_jobs"][0]["status"] == "pending"
    assert service.sync_execution(str(USER_ID), EXECUTION_ID)
    assert ai.calls[0] == ai.calls[1]
    assert len(ai.delivered) == 1


def test_acknowledgment_recovers_after_job_was_marked_delivered(plans_ready):
    db, ai = database(), AI()
    db.rows["execution_ai_sync_jobs"][0]["status"] = "synced"
    assert ExecutionAISyncService(db, ai).sync_execution(str(USER_ID), EXECUTION_ID)
    assert ai.calls == []


def test_retrospective_result_is_acknowledged_as_excluded_from_learning(plans_ready):
    db, ai = database(), AI()
    db.rows["execution_ai_sync_jobs"][0]["payload"]["learning_eligible"] = False
    assert ExecutionAISyncService(db, ai).sync_execution(str(USER_ID), EXECUTION_ID)
    assert db.rows["executions"][0]["ai_outcome_sync_status"] == "ineligible"


def test_sync_cannot_deliver_another_users_jobs(plans_ready):
    db, ai = database(), AI()
    assert not ExecutionAISyncService(db, ai).sync_execution(str(uuid4()), EXECUTION_ID)
    assert ai.calls == []
    assert db.rows["execution_ai_sync_jobs"][0]["status"] == "pending"


def test_primary_log_retry_does_not_duplicate_outcome(authenticated_client, monkeypatch):
    db = MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [],
    }, unique_keys={"executions": [("user_id", "idempotency_key")]})
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    request = outcome(idempotency_key=TASK_ID)
    first = authenticated_client.post("/executions", json=request)
    retry = authenticated_client.post("/executions", json=request)
    assert first.status_code == retry.status_code == 201
    assert first.json()["id"] == retry.json()["id"]
    assert first.json()["completion_ratio"] == "0.35"
    assert first.json()["interruption_count"] == 3
    assert len(db.rows["executions"]) == 1


def test_manual_log_over_active_timer_keeps_retry_key(authenticated_client, monkeypatch):
    db = MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [],
    })
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID})
    request = outcome(idempotency_key=TASK_ID)
    first = authenticated_client.post("/executions", json=request)
    retry = authenticated_client.post("/executions", json=request)
    assert first.status_code == retry.status_code == 201
    assert first.json()["id"] == started.json()["id"] == retry.json()["id"]
    assert len(db.rows["executions"]) == 1


def test_not_started_is_not_returned_as_an_active_execution(authenticated_client, monkeypatch):
    db = MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [],
    })
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    result = authenticated_client.post("/executions", json={
        "task_id": TASK_ID, "task_status": "failed", "outcome_status": "not_started",
    })
    assert result.status_code == 201
    assert result.json()["actual_start_time"] is None
    assert result.json()["actual_end_time"] is None
    assert authenticated_client.get("/executions?active=true").json() == []


def test_retry_endpoint_checks_ownership_and_auth(authenticated_client, monkeypatch):
    db = database()
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    monkeypatch.setattr(sync_module, "is_ai_supabase_configured", lambda: False)
    assert authenticated_client.post(f"/executions/{uuid4()}/ai-outcome").status_code == 404
    assert authenticated_client.post(f"/executions/{EXECUTION_ID}/ai-outcome").status_code == 503


def test_retry_requires_auth(client):
    assert client.post(f"/executions/{EXECUTION_ID}/ai-outcome").status_code == 401


def test_today_active_read_retries_pending_finished_results(authenticated_client, monkeypatch):
    db = database()
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    retried = []

    def retry(_db, result):
        retried.append(result["id"])
        return {**result, "ai_outcome_sync_status": "synced"}

    monkeypatch.setattr(executions, "sync_execution_ai_safely", retry)
    assert authenticated_client.get("/executions?active=true").json() == []
    assert retried == [EXECUTION_ID]


def test_active_execution_cannot_be_relabelled_as_never_started(authenticated_client, monkeypatch):
    db = MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [],
    })
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    result = authenticated_client.patch(f"/executions/{started['id']}/complete", json={
        "task_status": "failed", "outcome_status": "not_started",
    })
    assert result.status_code == 422
    assert db.rows["executions"][0]["actual_start_time"] == started["actual_start_time"]
    assert db.rows["tasks"][0]["task_status"] == "pending"


def test_not_started_correction_requires_real_times_before_claiming_completion(
    authenticated_client, monkeypatch,
):
    db = database()
    db.rows["executions"][0].update({
        "outcome_status": "not_started", "actual_start_time": None,
        "actual_end_time": None, "ai_outcome_sync_status": "unlinked",
    })
    monkeypatch.setattr(executions, "_require_db", lambda: db)
    result = authenticated_client.patch(f"/executions/{EXECUTION_ID}", json={
        "task_status": "success",
    })
    assert result.status_code == 422
    assert db.rows["executions"][0]["outcome_status"] == "not_started"
