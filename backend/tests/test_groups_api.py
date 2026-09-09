"""Group scheduling API tests (GitHub issue #6).

Every group-scoped route must behave as if non-member groups do not exist.
"""

from __future__ import annotations

import re
from typing import cast

import pytest
from fastapi.testclient import TestClient
from supabase import Client

from app.dependencies.database import get_auth_database
from app.main import app
from app.repositories.group_repository import GroupRepository
from app.routes.groups import get_group_service
from app.services.group_service import GroupService

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

OTHER_ID = "99999999-9999-4999-8999-999999999999"
STRANGER_ID = "88888888-8888-4888-8888-888888888888"
OWN_GROUP_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
FOREIGN_GROUP_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
OWN_TASK_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
FOREIGN_TASK_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
INVITE_CODE_PATTERN = re.compile(r"^[A-Z0-9]{8}$")
NOW = "2026-09-05T12:00:00+00:00"


def _seed_rows() -> dict[str, list[dict]]:
    return {
        "profiles": [
            {"id": str(USER_ID), "display_name": "Yen"},
            {"id": OTHER_ID, "display_name": "Alex"},
        ],
        "groups": [
            {
                "id": OWN_GROUP_ID,
                "owner_id": str(USER_ID),
                "name": "Study & Work Group",
                "invite_code": "ABCD2345",
                "created_at": "2026-09-01T10:00:00+00:00",
            },
            {
                "id": FOREIGN_GROUP_ID,
                "owner_id": OTHER_ID,
                "name": "Someone else's group",
                "invite_code": "WXYZ6789",
                "created_at": "2026-09-02T10:00:00+00:00",
            },
        ],
        "group_members": [
            {
                "group_id": OWN_GROUP_ID,
                "user_id": str(USER_ID),
                "role": "owner",
                "joined_at": "2026-09-01T10:00:00+00:00",
            },
            {
                "group_id": OWN_GROUP_ID,
                "user_id": OTHER_ID,
                "role": "member",
                "joined_at": "2026-09-01T11:00:00+00:00",
            },
            {
                "group_id": FOREIGN_GROUP_ID,
                "user_id": OTHER_ID,
                "role": "owner",
                "joined_at": "2026-09-02T10:00:00+00:00",
            },
        ],
        "group_tasks": [
            {
                "id": OWN_TASK_ID,
                "group_id": OWN_GROUP_ID,
                "created_by": str(USER_ID),
                "assigned_to": OTHER_ID,
                "title": "Review project proposal",
                "category": "Work",
                "priority": "high",
                "status": "pending",
                "due_date": "2026-09-06",
                "due_time": "15:00:00",
                "created_at": "2026-09-01T12:00:00+00:00",
                "updated_at": "2026-09-01T12:00:00+00:00",
            },
            {
                "id": FOREIGN_TASK_ID,
                "group_id": FOREIGN_GROUP_ID,
                "created_by": OTHER_ID,
                "assigned_to": None,
                "title": "Private task",
                "category": "Other",
                "priority": "low",
                "status": "pending",
                "due_date": None,
                "due_time": None,
                "created_at": "2026-09-02T12:00:00+00:00",
                "updated_at": "2026-09-02T12:00:00+00:00",
            },
        ],
    }


def _use_memory_database() -> MemoryDatabase:
    database = MemoryDatabase(
        _seed_rows(),
        unique_keys={
            "groups": [("invite_code",)],
            "group_members": [("group_id", "user_id")],
        },
        # Mirror the DEFAULT clauses in supabase/group_scheduling_schema.sql.
        column_defaults={
            "group_members": {"role": "member", "joined_at": NOW},
            "group_tasks": {
                "category": "Other",
                "priority": "medium",
                "status": "pending",
                "assigned_to": None,
                "due_date": None,
                "due_time": None,
                "updated_at": NOW,
            },
        },
        now=NOW,
    )
    app.dependency_overrides[get_group_service] = lambda: GroupService(
        GroupRepository(cast(Client, database))
    )
    return database


def _memberships(database: MemoryDatabase, group_id: str) -> list[dict]:
    return [row for row in database.rows["group_members"] if row["group_id"] == group_id]


# ── authentication ──────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/groups"),
        ("post", "/groups"),
        ("post", "/groups/join"),
        ("get", f"/groups/{OWN_GROUP_ID}"),
        ("post", f"/groups/{OWN_GROUP_ID}/tasks"),
    ],
)
def test_groups_require_auth(client: TestClient, method: str, path: str) -> None:
    app.dependency_overrides[get_auth_database] = lambda: object()
    _use_memory_database()

    response = client.request(method, path, headers={"X-User-Id": str(USER_ID)})

    assert response.status_code == 401


# ── groups ──────────────────────────────────────────────────────────────────
def test_create_group_makes_creator_owner_member(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.post("/groups", json={"name": "  Capstone crew  "})

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Capstone crew"
    assert body["owner_id"] == str(USER_ID)
    assert body["role"] == "owner"
    assert INVITE_CODE_PATTERN.fullmatch(body["invite_code"])
    memberships = _memberships(database, body["id"])
    assert [(m["user_id"], m["role"]) for m in memberships] == [(str(USER_ID), "owner")]


@pytest.mark.parametrize("payload", [{"name": ""}, {"name": "   "}, {"name": "x" * 81}, {}])
def test_create_group_rejects_invalid_name(authenticated_client: TestClient, payload: dict) -> None:
    _use_memory_database()

    response = authenticated_client.post("/groups", json=payload)

    assert response.status_code == 422


def test_create_group_rejects_unknown_fields(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.post("/groups", json={"name": "Crew", "owner_id": OTHER_ID})

    assert response.status_code == 422


def test_list_groups_returns_only_memberships(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.get("/groups")

    assert response.status_code == 200
    assert [(group["id"], group["role"]) for group in response.json()] == [(OWN_GROUP_ID, "owner")]


def test_get_group_detail_includes_members_and_tasks(
    authenticated_client: TestClient,
) -> None:
    _use_memory_database()

    response = authenticated_client.get(f"/groups/{OWN_GROUP_ID}")

    assert response.status_code == 200
    body = response.json()
    assert body["group"]["id"] == OWN_GROUP_ID
    assert body["group"]["role"] == "owner"
    assert body["group"]["invite_code"] == "ABCD2345"
    assert [(m["user_id"], m["role"], m["display_name"]) for m in body["members"]] == [
        (str(USER_ID), "owner", "Yen"),
        (OTHER_ID, "member", "Alex"),
    ]
    assert [task["id"] for task in body["tasks"]] == [OWN_TASK_ID]
    assert body["tasks"][0]["assignee_name"] == "Alex"
    assert body["tasks"][0]["due_date"] == "2026-09-06"
    assert body["tasks"][0]["due_time"] == "15:00:00"


def test_get_group_as_non_member_returns_404(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.get(f"/groups/{FOREIGN_GROUP_ID}")

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


def test_get_group_with_malformed_id_returns_422(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.get("/groups/not-a-uuid")

    assert response.status_code == 422


# ── joining ─────────────────────────────────────────────────────────────────
def test_join_group_with_valid_code_adds_member(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    joined = authenticated_client.post("/groups/join", json={"invite_code": "WXYZ6789"})
    listed = authenticated_client.get("/groups")
    detail = authenticated_client.get(f"/groups/{FOREIGN_GROUP_ID}")

    assert joined.status_code == 200
    assert joined.json()["id"] == FOREIGN_GROUP_ID
    assert joined.json()["role"] == "member"
    assert {group["id"] for group in listed.json()} == {OWN_GROUP_ID, FOREIGN_GROUP_ID}
    assert detail.status_code == 200
    assert len(_memberships(database, FOREIGN_GROUP_ID)) == 2


def test_join_group_normalizes_code_case_and_whitespace(
    authenticated_client: TestClient,
) -> None:
    _use_memory_database()

    response = authenticated_client.post("/groups/join", json={"invite_code": " wxyz6789 "})

    assert response.status_code == 200
    assert response.json()["id"] == FOREIGN_GROUP_ID


def test_join_group_with_unknown_code_returns_404(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.post("/groups/join", json={"invite_code": "NOPE0000"})

    assert response.status_code == 404
    assert response.json()["detail"] == "Invalid invite code."


@pytest.mark.parametrize("code", ["", "abc", "TOO-LONG-CODE", "ABCD-234"])
def test_join_group_with_malformed_code_returns_422(
    authenticated_client: TestClient, code: str
) -> None:
    _use_memory_database()

    response = authenticated_client.post("/groups/join", json={"invite_code": code})

    assert response.status_code == 422


def test_join_group_when_already_member_returns_409(
    authenticated_client: TestClient,
) -> None:
    database = _use_memory_database()

    response = authenticated_client.post("/groups/join", json={"invite_code": "ABCD2345"})

    assert response.status_code == 409
    assert response.json()["code"] == "conflict"
    assert len(_memberships(database, OWN_GROUP_ID)) == 2


# ── group tasks ─────────────────────────────────────────────────────────────
def test_create_task_in_member_group(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.post(
        f"/groups/{OWN_GROUP_ID}/tasks",
        json={
            "title": "  Prepare presentation slides ",
            "category": "Work",
            "priority": "high",
            "due_date": "2026-09-07",
            "due_time": "14:00",
            "assigned_to": OTHER_ID,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["title"] == "Prepare presentation slides"
    assert body["group_id"] == OWN_GROUP_ID
    assert body["created_by"] == str(USER_ID)
    assert body["assigned_to"] == OTHER_ID
    assert body["assignee_name"] == "Alex"
    assert body["status"] == "pending"
    assert body["due_date"] == "2026-09-07"
    assert body["due_time"] == "14:00:00"
    stored = [row for row in database.rows["group_tasks"] if row["id"] == body["id"]]
    assert stored[0]["group_id"] == OWN_GROUP_ID


def test_create_task_defaults_and_unassigned(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.post(
        f"/groups/{OWN_GROUP_ID}/tasks", json={"title": "Send weekly report"}
    )

    assert response.status_code == 201
    body = response.json()
    assert body["category"] == "Other"
    assert body["priority"] == "medium"
    assert body["assigned_to"] is None
    assert body["assignee_name"] is None
    assert body["due_date"] is None
    assert body["due_time"] is None


def test_create_task_in_non_member_group_returns_404(
    authenticated_client: TestClient,
) -> None:
    database = _use_memory_database()

    response = authenticated_client.post(
        f"/groups/{FOREIGN_GROUP_ID}/tasks", json={"title": "Sneaky task"}
    )

    assert response.status_code == 404
    assert len(database.rows["group_tasks"]) == 2


def test_create_task_assigned_to_non_member_returns_422(
    authenticated_client: TestClient,
) -> None:
    database = _use_memory_database()

    response = authenticated_client.post(
        f"/groups/{OWN_GROUP_ID}/tasks",
        json={"title": "Task", "assigned_to": STRANGER_ID},
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "Assignee must be a member of this group."
    assert len(database.rows["group_tasks"]) == 2


@pytest.mark.parametrize(
    "payload",
    [
        {"title": ""},
        {"title": "x" * 201},
        {"title": "Task", "priority": "urgent"},
        {"title": "Task", "due_date": "tomorrow"},
        {"title": "Task", "due_time": "3pm"},
        {"title": "Task", "status": "success"},
        {"title": "Task", "group_id": FOREIGN_GROUP_ID},
    ],
)
def test_create_task_rejects_invalid_payload(
    authenticated_client: TestClient, payload: dict
) -> None:
    _use_memory_database()

    response = authenticated_client.post(f"/groups/{OWN_GROUP_ID}/tasks", json=payload)

    assert response.status_code == 422


def test_update_task_status_by_member(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={"status": "success"}
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["title"] == "Review project proposal"
    assert body["assignee_name"] == "Alex"
    assert body["updated_at"] != "2026-09-01T12:00:00+00:00"
    assert database.rows["group_tasks"][0]["status"] == "success"


def test_update_task_can_reassign_and_unassign(authenticated_client: TestClient) -> None:
    _use_memory_database()

    reassigned = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={"assigned_to": str(USER_ID)}
    )
    unassigned = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={"assigned_to": None}
    )

    assert reassigned.status_code == 200
    assert reassigned.json()["assigned_to"] == str(USER_ID)
    assert reassigned.json()["assignee_name"] == "Yen"
    assert unassigned.status_code == 200
    assert unassigned.json()["assigned_to"] is None
    assert unassigned.json()["assignee_name"] is None


def test_update_task_to_non_member_returns_422(authenticated_client: TestClient) -> None:
    _use_memory_database()

    response = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={"assigned_to": STRANGER_ID}
    )

    assert response.status_code == 422


def test_update_task_with_invalid_status_returns_422(
    authenticated_client: TestClient,
) -> None:
    _use_memory_database()

    response = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={"status": "done"}
    )

    assert response.status_code == 422


def test_update_task_with_empty_body_returns_current_task(
    authenticated_client: TestClient,
) -> None:
    _use_memory_database()

    response = authenticated_client.patch(f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}", json={})

    assert response.status_code == 200
    assert response.json()["updated_at"] == "2026-09-01T12:00:00+00:00"


def test_update_task_in_foreign_group_returns_404(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.patch(
        f"/groups/{FOREIGN_GROUP_ID}/tasks/{FOREIGN_TASK_ID}", json={"status": "success"}
    )

    assert response.status_code == 404
    assert database.rows["group_tasks"][1]["status"] == "pending"


def test_update_task_id_from_other_group_returns_404(
    authenticated_client: TestClient,
) -> None:
    """A member cannot reach a foreign task by pairing it with their own group id."""
    database = _use_memory_database()

    response = authenticated_client.patch(
        f"/groups/{OWN_GROUP_ID}/tasks/{FOREIGN_TASK_ID}", json={"status": "success"}
    )

    assert response.status_code == 404
    assert database.rows["group_tasks"][1]["status"] == "pending"


def test_delete_task_by_member(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.delete(f"/groups/{OWN_GROUP_ID}/tasks/{OWN_TASK_ID}")

    assert response.status_code == 204
    assert [row["id"] for row in database.rows["group_tasks"]] == [FOREIGN_TASK_ID]


def test_delete_task_in_foreign_group_returns_404(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.delete(f"/groups/{FOREIGN_GROUP_ID}/tasks/{FOREIGN_TASK_ID}")

    assert response.status_code == 404
    assert len(database.rows["group_tasks"]) == 2


# ── deleting groups ─────────────────────────────────────────────────────────
def test_delete_group_as_owner(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.delete(f"/groups/{OWN_GROUP_ID}")

    assert response.status_code == 204
    assert [group["id"] for group in database.rows["groups"]] == [FOREIGN_GROUP_ID]


def test_delete_group_as_member_returns_403(authenticated_client: TestClient) -> None:
    database = _use_memory_database()
    authenticated_client.post("/groups/join", json={"invite_code": "WXYZ6789"})

    response = authenticated_client.delete(f"/groups/{FOREIGN_GROUP_ID}")

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"
    assert len(database.rows["groups"]) == 2


def test_delete_group_as_non_member_returns_404(authenticated_client: TestClient) -> None:
    database = _use_memory_database()

    response = authenticated_client.delete(f"/groups/{FOREIGN_GROUP_ID}")

    assert response.status_code == 404
    assert len(database.rows["groups"]) == 2
