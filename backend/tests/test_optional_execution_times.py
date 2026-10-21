"""Completing a plan without a timer: optional actual times are stored as unknown, never guessed."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.routes import executions
from app.schemas.execution import ExecutionComplete, ExecutionCreate
from app.services.duration_service import DurationService

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

TASK_ID = str(uuid4())
COMPLETED = {"task_status": "success", "outcome_status": "completed"}
NOT_COMPLETED = {"task_status": "failed", "outcome_status": "abandoned", "completion_ratio": 0}


def _iso(delta_minutes: int = 0) -> str:
    return (datetime.now(timezone.utc) + timedelta(minutes=delta_minutes)).isoformat()


@pytest.fixture
def db(monkeypatch) -> MemoryDatabase:
    database = MemoryDatabase({
        "tasks": [{"id": TASK_ID, "user_id": str(USER_ID), "task_status": "pending"}],
        "executions": [],
    })
    monkeypatch.setattr(executions, "_require_db", lambda: database)
    return database


def _log(client, **body):
    return client.post("/executions", json={"task_id": TASK_ID, "idempotency_key": TASK_ID, **body})


def test_completed_with_reported_finish_stores_end_only(authenticated_client, db):
    finished = _iso(-10)
    result = _log(authenticated_client, **COMPLETED, actual_end_time=finished)
    assert result.status_code == 201
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] is None  # no invented start
    assert datetime.fromisoformat(stored["actual_end_time"]) == datetime.fromisoformat(finished)
    assert stored["task_status"] == "success" and stored["outcome_status"] == "completed"
    assert db.rows["tasks"][0]["task_status"] == "success"


def test_completed_blank_stores_no_actual_times(authenticated_client, db):
    result = _log(authenticated_client, **COMPLETED)
    assert result.status_code == 201
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] is None and stored["actual_end_time"] is None
    assert float(stored["completion_ratio"]) == 1


def test_not_completed_with_minutes_and_no_reason(authenticated_client, db):
    result = _log(authenticated_client, **NOT_COMPLETED, active_minutes=20, stopped_early=True)
    assert result.status_code == 201
    stored = db.rows["executions"][0]
    assert stored["active_minutes"] == 20
    assert stored["failure_reason"] is None
    assert stored["actual_start_time"] is None and stored["actual_end_time"] is None
    assert db.rows["tasks"][0]["task_status"] == "failed"


def test_not_completed_blank_is_unknown_not_not_started(authenticated_client, db):
    result = _log(authenticated_client, **NOT_COMPLETED)
    assert result.status_code == 201
    stored = db.rows["executions"][0]
    assert stored["outcome_status"] == "abandoned"
    assert stored["active_minutes"] is None  # unknown, distinct from a reported 0
    assert stored["task_status"] == "failed"


def test_reported_zero_minutes_and_optional_reason_are_kept(authenticated_client, db):
    result = _log(
        authenticated_client, **NOT_COMPLETED, active_minutes=0, failure_reason="interruption"
    )
    assert result.status_code == 201
    assert db.rows["executions"][0]["active_minutes"] == 0
    assert db.rows["executions"][0]["failure_reason"] == "interruption"


@pytest.mark.parametrize("body", [
    {**COMPLETED, "actual_end_time": _iso(60)},
    {**COMPLETED, "actual_start_time": _iso(-5), "actual_end_time": _iso(-60)},
    {**COMPLETED, "actual_end_unknown": True, "actual_end_time": _iso(-5)},
    {"task_status": "failed", "outcome_status": "not_started", "actual_end_time": _iso(-5)},
    {**NOT_COMPLETED, "active_minutes": -1},
    {**NOT_COMPLETED, "failure_reason": "invented"},
])
def test_invalid_optional_times_are_still_rejected(body):
    with pytest.raises(ValidationError):
        ExecutionCreate.model_validate({"task_id": TASK_ID, **body})


def test_full_reported_range_still_validates_active_minutes():
    with pytest.raises(ValidationError):
        ExecutionComplete.model_validate({
            **NOT_COMPLETED, "actual_start_time": _iso(-10), "actual_end_time": _iso(),
            "active_minutes": 30,
        })


def test_legacy_timer_with_unknown_finish_keeps_start_and_does_not_stamp_submit_time(
    authenticated_client, db,
):
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    result = authenticated_client.patch(
        f"/executions/{started['id']}/complete", json={**COMPLETED, "actual_end_unknown": True},
    )
    assert result.status_code == 200
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] == started["actual_start_time"]
    assert stored["actual_end_time"] is None
    assert authenticated_client.get("/executions?active=true").json() == []


def test_legacy_timer_with_reported_finish_keeps_recorded_start(authenticated_client, db):
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    finished = _iso(1)
    result = authenticated_client.patch(
        f"/executions/{started['id']}/complete", json={**COMPLETED, "actual_end_time": finished},
    )
    assert result.status_code == 200
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] == started["actual_start_time"]
    assert datetime.fromisoformat(stored["actual_end_time"]) == datetime.fromisoformat(finished)


def test_legacy_timer_finish_before_recorded_start_is_rejected(authenticated_client, db):
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    result = authenticated_client.patch(
        f"/executions/{started['id']}/complete", json={**COMPLETED, "actual_end_time": _iso(-120)},
    )
    assert result.status_code == 422
    assert db.rows["executions"][0]["task_status"] is None


def test_legacy_timer_not_completed_via_manual_log_keeps_start(authenticated_client, db):
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    result = _log(authenticated_client, **NOT_COMPLETED, active_minutes=5, actual_end_unknown=True)
    assert result.status_code == 201
    assert result.json()["id"] == started["id"]
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] == started["actual_start_time"]
    assert stored["actual_end_time"] is None and stored["active_minutes"] == 5


def test_older_clients_still_get_server_finish_time(authenticated_client, db):
    started = authenticated_client.post("/executions/start", json={"task_id": TASK_ID}).json()
    result = authenticated_client.patch(f"/executions/{started['id']}/complete", json=COMPLETED)
    assert result.status_code == 200
    assert db.rows["executions"][0]["actual_end_time"] is not None


class _History:
    def __init__(self, rows):
        self.rows = rows

    def list_observations(self, _user_id):
        return self.rows


def test_duration_recommendations_ignore_records_without_a_measured_range():
    now = datetime(2026, 10, 6, tzinfo=timezone.utc)
    start = now - timedelta(days=1)

    def observation(**times):
        return {
            "task_id": str(uuid4()), "outcome_status": "completed", "task_status": "success",
            "actual_start_time": None, "actual_end_time": None, **times,
            "plan": {"title": "Read", "category": "Study", "planned_duration_minutes": 30,
                     "captured_at": (start - timedelta(hours=1)).isoformat()},
        }

    measured = [
        observation(actual_start_time=start.isoformat(),
                    actual_end_time=(start + timedelta(minutes=m)).isoformat())
        for m in (34, 36, 38)
    ]
    unknown = [observation(), observation(actual_end_time=start.isoformat()),
               observation(actual_start_time=start.isoformat())]
    result = DurationService(_History(measured + unknown)).get(
        USER_ID, "Read", "Study", 30, now=now
    )
    assert result.available and result.sample_count == 3
    only_unknown = DurationService(_History(unknown)).get(USER_ID, "Read", "Study", 30, now=now)
    assert only_unknown.sample_count == 0


# ── Editing a logged outcome (PATCH /executions/{id}) ──────────────────────────
EXECUTION_ID = str(uuid4())


def _logged(db: MemoryDatabase, **changes) -> dict:
    row = {
        "id": EXECUTION_ID, "task_id": TASK_ID, "user_id": str(USER_ID),
        "task_status": "failed", "outcome_status": "abandoned", "completion_ratio": 0,
        "interruption_count": 0, "stopped_early": False, "failure_reason": None,
        "active_minutes": None, "actual_start_time": None, "actual_end_time": None,
        "ai_outcome_sync_status": "unlinked", "created_at": _iso(-60), **changes,
    }
    db.rows["executions"] = [row]
    return row


def _revise(client, **body):
    return client.patch(f"/executions/{EXECUTION_ID}", json=body)


def test_editing_reason_keeps_unknown_times_and_reported_minutes(authenticated_client, db):
    _logged(db, active_minutes=20)
    result = _revise(
        authenticated_client, **NOT_COMPLETED, failure_reason="interruption", active_minutes=20
    )
    assert result.status_code == 200
    stored = db.rows["executions"][0]
    assert stored["failure_reason"] == "interruption"
    assert stored["actual_start_time"] is None and stored["actual_end_time"] is None
    assert stored["active_minutes"] == 20


def test_editing_finish_only_record_keeps_start_unknown(authenticated_client, db):
    finished = _iso(-30)
    _logged(db, **COMPLETED, completion_ratio=1, actual_end_time=finished)
    corrected = _iso(-20)
    result = _revise(authenticated_client, **COMPLETED, actual_end_time=corrected)
    assert result.status_code == 200
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] is None
    assert datetime.fromisoformat(stored["actual_end_time"]) == datetime.fromisoformat(corrected)


def test_editing_legacy_start_only_record_keeps_start_and_unknown_finish(authenticated_client, db):
    started = _iso(-90)
    _logged(db, **COMPLETED, completion_ratio=1, actual_start_time=started)
    result = _revise(authenticated_client, **COMPLETED)
    assert result.status_code == 200
    stored = db.rows["executions"][0]
    assert stored["actual_start_time"] == started and stored["actual_end_time"] is None


def test_adding_finish_to_legacy_start_is_validated_against_the_stored_start(
    authenticated_client, db,
):
    _logged(db, **COMPLETED, completion_ratio=1, actual_start_time=_iso(-90))
    assert _revise(authenticated_client, **COMPLETED, actual_end_time=_iso(-120)).status_code == 422
    assert _revise(authenticated_client, **COMPLETED, actual_end_time=_iso(-30)).status_code == 200


def test_editing_record_with_both_times_still_validates_the_range(authenticated_client, db):
    _logged(db, actual_start_time=_iso(-60), actual_end_time=_iso(-30))
    too_many = _revise(authenticated_client, **NOT_COMPLETED, active_minutes=45)
    assert too_many.status_code == 422
    ok = _revise(authenticated_client, **NOT_COMPLETED, active_minutes=25, failure_reason="other")
    assert ok.status_code == 200
    assert db.rows["executions"][0]["actual_start_time"] is not None


def test_start_time_alone_cannot_be_in_the_future():
    with pytest.raises(ValidationError):
        ExecutionComplete.model_validate({**COMPLETED, "actual_start_time": _iso(60)})


# ── Interruption counts: null = not reported, 0 = reported zero ───────────────
def test_new_workflow_stores_unreported_interruptions_as_null(authenticated_client, db):
    result = _log(authenticated_client, **COMPLETED, interruption_count=None)
    assert result.status_code == 201
    assert result.json()["interruption_count"] is None
    assert db.rows["executions"][0]["interruption_count"] is None


def test_older_clients_without_the_field_still_record_zero():
    parsed = ExecutionCreate.model_validate({"task_id": TASK_ID, **COMPLETED})
    assert parsed.interruption_count == 0


def test_reported_zero_is_kept_and_not_started_is_a_confirmed_zero():
    assert ExecutionCreate.model_validate(
        {"task_id": TASK_ID, **NOT_COMPLETED, "interruption_count": 0}
    ).interruption_count == 0
    not_started = ExecutionCreate.model_validate(
        {"task_id": TASK_ID, "task_status": "failed", "outcome_status": "not_started",
         "interruption_count": None}
    )
    assert not_started.interruption_count == 0


def test_editing_keeps_an_unknown_interruption_count(authenticated_client, db):
    _logged(db, interruption_count=None)
    result = _revise(
        authenticated_client, **NOT_COMPLETED, interruption_count=None, failure_reason="other"
    )
    assert result.status_code == 200
    assert db.rows["executions"][0]["interruption_count"] is None


class _Rows:
    """Minimal query stub: every filter is accepted, execute() returns the table's rows."""

    def __init__(self, tables):
        self.tables = tables

    def table(self, name):
        rows = self.tables.get(name, [])

        class Query:
            def __getattr__(self, _name):
                return lambda *args, **kwargs: self

            def execute(self):
                return SimpleNamespace(data=rows)

        return Query()


def _summary(executions):
    from app.services.analytics_service import AnalyticsService

    today = datetime.now(timezone.utc).date().isoformat()
    tasks = [{"id": str(uuid4()), "task_status": "success", "task_category": "Study",
              "planned_date": today, "planned_start_time": "9:00 AM",
              "planned_duration_min": 30, "importance": 3}]
    return AnalyticsService(_Rows({"tasks": tasks, "executions": executions})).get_summary(
        str(USER_ID), "week"
    )


def test_analytics_average_ignores_unreported_interruptions():
    summary = _summary(
        [{"interruption_count": 4}, {"interruption_count": 0}, {"interruption_count": None}]
    )
    assert summary["avg_interruptions"] == 2.0  # (4 + 0) / 2, the unknown is excluded


def test_analytics_average_is_unknown_when_nothing_was_reported():
    assert _summary([{"interruption_count": None}])["avg_interruptions"] is None
    assert _summary([])["avg_interruptions"] is None


def test_coach_interruption_statistics_skip_unknown_counts():
    from app.services.coaching_context_service import _reported_interruptions

    rows = [{"interruption_count": 2}, {"interruption_count": 0}, {"interruption_count": None}, {}]
    assert _reported_interruptions(rows) == [2, 0]


def test_ai_outcome_response_accepts_an_unknown_interruption_count():
    from app.schemas.ai_outcome import OutcomeResponse

    parsed = OutcomeResponse.model_validate({
        "id": str(uuid4()), "plan_input_id": str(uuid4()), "outcome_status": "completed",
        "actual_start": None, "actual_end": None, "active_minutes": None,
        "completion_ratio": 1, "interruption_count": None, "stopped_early": False,
        "user_note": None, "recorded_at": _iso(),
    })
    assert parsed.interruption_count is None
