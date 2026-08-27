from __future__ import annotations

from copy import deepcopy
from datetime import datetime
from types import SimpleNamespace
from typing import Any
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.dependencies.database import get_auth_database
from app.main import app
from app.routes import executions, tasks

from .conftest import USER_ID


class MemoryQuery:
    def __init__(self, database: MemoryDatabase, table_name: str) -> None:
        self.database = database
        self.table_name = table_name
        self.operation = "select"
        self.filters: list[tuple[str, Any]] = []
        self.null_filters: list[str] = []
        self.values: dict[str, Any] = {}
        self.descending = False
        self.row_limit: int | None = None

    def select(self, _columns: str) -> MemoryQuery:
        return self

    def eq(self, column: str, value: Any) -> MemoryQuery:
        self.filters.append((column, str(value)))
        return self

    def is_(self, column: str, value: str) -> MemoryQuery:
        assert value == "null"
        self.null_filters.append(column)
        return self

    def order(self, _column: str, desc: bool = False) -> MemoryQuery:
        self.descending = desc
        return self

    def limit(self, count: int) -> MemoryQuery:
        self.row_limit = count
        return self

    def insert(self, values: dict[str, Any]) -> MemoryQuery:
        self.operation = "insert"
        self.values = deepcopy(values)
        return self

    def update(self, values: dict[str, Any]) -> MemoryQuery:
        self.operation = "update"
        self.values = deepcopy(values)
        return self

    def execute(self) -> SimpleNamespace:
        rows = self.database.rows[self.table_name]
        if self.operation == "insert":
            created = {
                "id": str(uuid4()),
                "created_at": "2026-08-26T12:00:00+00:00",
                **self.values,
            }
            rows.append(created)
            return SimpleNamespace(data=[deepcopy(created)])

        matches = [row for row in rows if self._matches(row)]
        if self.descending:
            matches = list(reversed(matches))
        if self.row_limit is not None:
            matches = matches[: self.row_limit]

        if self.operation == "update":
            for row in matches:
                row.update(self.values)
            return SimpleNamespace(data=deepcopy(matches))
        return SimpleNamespace(data=deepcopy(matches))

    def _matches(self, row: dict[str, Any]) -> bool:
        return all(str(row.get(key)) == value for key, value in self.filters) and all(
            row.get(key) is None for key in self.null_filters
        )


class MemoryDatabase:
    def __init__(self) -> None:
        self.rows: dict[str, list[dict[str, Any]]] = {
            "tasks": [
                {
                    "id": "task-owned",
                    "user_id": str(USER_ID),
                    "title": "Mobile task",
                    "task_category": "Other",
                    "planned_start_time": "9:00 AM",
                    "planned_date": "2026-08-26",
                    "planned_duration_min": 30,
                    "importance": 3,
                    "energy_level": 3,
                    "focus_level": 3,
                    "total_tasks_today": 1,
                    "task_status": "pending",
                    "created_at": "2026-08-26T11:00:00+00:00",
                },
                {
                    "id": "task-other",
                    "user_id": "99999999-9999-4999-8999-999999999999",
                    "task_status": "pending",
                },
            ],
            "executions": [],
        }

    def table(self, table_name: str) -> MemoryQuery:
        return MemoryQuery(self, table_name)


def _use_memory_database(monkeypatch) -> MemoryDatabase:
    database = MemoryDatabase()
    monkeypatch.setattr(tasks, "_require_db", lambda: database)
    monkeypatch.setattr(executions, "_require_db", lambda: database)
    return database


@pytest.mark.parametrize("path", ["/tasks", "/executions", "/analytics/summary"])
def test_v1_rejects_spoofed_user_header(client: TestClient, path: str) -> None:
    app.dependency_overrides[get_auth_database] = lambda: object()

    response = client.get(
        path,
        headers={"X-User-Id": "99999999-9999-4999-8999-999999999999"},
    )

    assert response.status_code == 401


def test_mobile_start_is_idempotent_and_scoped(
    authenticated_client: TestClient, monkeypatch
) -> None:
    database = _use_memory_database(monkeypatch)

    first = authenticated_client.post("/executions/start", json={"task_id": "task-owned"})
    second = authenticated_client.post("/executions/start", json={"task_id": "task-owned"})
    other = authenticated_client.post("/executions/start", json={"task_id": "task-other"})

    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["id"] == second.json()["id"]
    assert len(database.rows["executions"]) == 1
    assert other.status_code == 404
    assert datetime.fromisoformat(first.json()["actual_start_time"]).tzinfo is not None


def test_mobile_completion_updates_owned_execution_and_task(
    authenticated_client: TestClient, monkeypatch
) -> None:
    database = _use_memory_database(monkeypatch)
    started = authenticated_client.post(
        "/executions/start", json={"task_id": "task-owned"}
    ).json()

    missing_reason = authenticated_client.patch(
        f"/executions/{started['id']}/complete",
        json={"task_status": "failed", "stopped_early": True},
    )
    completed = authenticated_client.patch(
        f"/executions/{started['id']}/complete",
        json={
            "task_status": "failed",
            "stopped_early": True,
            "failure_reason": "underestimated_time",
        },
    )
    active = authenticated_client.get("/executions?active=true")

    assert missing_reason.status_code == 422
    assert completed.status_code == 200
    assert completed.json()["failure_reason"] == "underestimated_time"
    assert completed.json()["actual_end_time"] is not None
    assert active.json() == []
    assert database.rows["tasks"][0]["task_status"] == "failed"


def test_task_list_never_returns_another_users_plan(
    authenticated_client: TestClient, monkeypatch
) -> None:
    _use_memory_database(monkeypatch)

    response = authenticated_client.get("/tasks?date=2026-08-26")

    assert response.status_code == 200
    assert [row["id"] for row in response.json()] == ["task-owned"]
