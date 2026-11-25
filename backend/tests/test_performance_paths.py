from unittest.mock import Mock

import pytest
from fastapi import BackgroundTasks

from app.routes import tasks
from app.schemas.group import GroupPersonalPlanRequest
from app.services.ai_v2_ml_service import get_ai_v2_ml_service

from . import test_group_personal_planning as group_cases
from .conftest import USER_ID


def test_batch_predictions_preserve_single_plan_results(monkeypatch):
    _, planner, _, _ = group_cases.setup.__wrapped__(monkeypatch)
    model = get_ai_v2_ml_service()
    if not model.is_ready:
        model.load()
    body = GroupPersonalPlanRequest(**group_cases.BODY)
    task = {"title": "Synthetic benchmark", "category": "Work", "priority": "medium"}
    plans = [
        planner._plan(task, body.model_copy(update={"planned_duration_minutes": duration}), [])
        for duration in (30, 60, 90)
    ]
    batch = model.predict_many(plans)
    for plan, result in zip(plans, batch, strict=True):
        single = model.predict(plan)
        assert result["success_probability"] == pytest.approx(single["success_probability"])
        assert result["failure_reason_probabilities"] == pytest.approx(
            single["failure_reason_probabilities"]
        )
    assert model.predict_many([]) == []


def test_task_list_defers_sync_until_after_response(monkeypatch):
    db = object()
    monkeypatch.setattr(tasks, "_require_db", lambda: db)
    monkeypatch.setattr(
        tasks.TaskService,
        "list_for_user",
        lambda *a, **k: [{"id": "one", "ai_sync_status": "pending"}],
    )
    sync = Mock()
    monkeypatch.setattr(tasks, "sync_task_ai_safely", sync)
    background = BackgroundTasks()
    result = tasks.list_tasks(USER_ID, background, None)
    assert result[0]["ai_sync_status"] == "pending"
    sync.assert_not_called()
    assert len(background.tasks) == 1


def test_request_timing_includes_auth_and_sanitized_route(monkeypatch):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.core.timing import RequestTimingMiddleware, timed

    application = FastAPI()
    application.add_middleware(RequestTimingMiddleware)

    @timed("auth")
    def verify():
        return True

    @application.get("/example/{item_id}")
    def example(item_id: str):
        return {"verified": verify()}

    response = TestClient(application).get("/example/private-value?token=secret")
    assert response.status_code == 200
    timing = response.headers["Server-Timing"]
    assert "app;dur=" in timing
    assert "auth;dur=" in timing
    assert "private-value" not in timing
    assert "secret" not in timing


def test_personalization_history_has_a_bounded_recent_scan():
    from typing import cast

    from supabase import Client

    from app.repositories.personalization_repository import PersonalizationRepository

    from .test_repositories import PaginatedDatabase, PaginatedQuery

    class Query(PaginatedQuery):
        def order(self, *_args, **_kwargs):
            return self

        def in_(self, *_args):
            return self

    class Database(PaginatedDatabase):
        def table(self, _name):
            return Query(self.rows, self.calls, self.max_page_size)

    database = Database([{"id": str(i)} for i in range(2000)])
    result = PersonalizationRepository(cast(Client, database)).list_completed_tasks(USER_ID)
    assert len(result) == 400
    assert database.calls == [(0, 399)]
