"""Group scheduling business rules.

The backend talks to Supabase with a service-role client, so Row Level Security
does not apply. Every group-scoped operation therefore verifies the caller's
membership here before reading or writing any group data. Non-members receive
404 so that group existence is never revealed.
"""

from __future__ import annotations

import logging
import secrets
from datetime import date, datetime, time, timezone
from typing import Any
from uuid import UUID

from ..core.errors import (
    DomainValidationError,
    PermissionDeniedError,
    ResourceConflictError,
    ResourceNotFoundError,
)
from ..repositories.group_repository import GroupRepository, JsonRow
from ..schemas.group import GroupCreate, GroupJoinRequest, GroupTaskCreate, GroupTaskUpdate

logger = logging.getLogger(__name__)

# No 0/O or 1/I so codes are unambiguous when read aloud or copied by hand.
_INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_INVITE_CODE_LENGTH = 8
_INVITE_CODE_ATTEMPTS = 5


def _generate_invite_code() -> str:
    return "".join(secrets.choice(_INVITE_ALPHABET) for _ in range(_INVITE_CODE_LENGTH))


def _serialize_task_fields(data: dict[str, Any]) -> JsonRow:
    """Convert validated Pydantic values into PostgREST-friendly JSON."""
    serialized: JsonRow = {}
    for key, value in data.items():
        if isinstance(value, UUID):
            serialized[key] = str(value)
        elif isinstance(value, (date, time)):
            serialized[key] = value.isoformat()
        else:
            serialized[key] = value
    return serialized


class GroupService:
    def __init__(self, groups: GroupRepository) -> None:
        self.groups = groups

    # ── groups ──────────────────────────────────────────────────────────────
    def create_group(self, user_id: UUID, body: GroupCreate) -> JsonRow:
        owner_id = str(user_id)
        group = self._create_group_with_unique_code(owner_id, body.name)
        try:
            self.groups.add_member(group_id=str(group["id"]), user_id=owner_id, role="owner")
        except Exception:
            self._discard_group_safely(str(group["id"]), owner_id)
            raise
        return {**group, "role": "owner"}

    def list_groups(self, user_id: UUID) -> list[JsonRow]:
        memberships = self.groups.list_memberships_for_user(str(user_id))
        roles = {str(row["group_id"]): row["role"] for row in memberships}
        groups = self.groups.list_groups_by_ids(list(roles))
        listed = [{**group, "role": roles[str(group["id"])]} for group in groups]
        return sorted(listed, key=lambda group: str(group.get("created_at", "")))

    def get_group_detail(self, user_id: UUID, group_id: UUID) -> JsonRow:
        membership = self._require_member(group_id, user_id)
        group = self.groups.get_group(str(group_id))
        if group is None:
            raise ResourceNotFoundError("Group not found.")

        members = self.groups.list_members(str(group_id))
        tasks = self.groups.list_tasks(str(group_id))
        assignment_rows = self.groups.list_task_assignees(str(group_id))
        assignee_ids = [str(row["user_id"]) for row in assignment_rows]
        profiles = self.groups.get_profiles(
            [str(row["user_id"]) for row in members]
            + assignee_ids
        )
        assignments_by_task: dict[str, list[str]] = {}
        for row in assignment_rows:
            assignments_by_task.setdefault(str(row["task_id"]), []).append(str(row["user_id"]))
        return {
            "group": {**group, "role": membership["role"]},
            "members": [
                {
                    **row,
                    "display_name": profiles.get(str(row["user_id"]), {}).get("display_name"),
                    "avatar_url": profiles.get(str(row["user_id"]), {}).get("avatar_url"),
                }
                for row in members
            ],
            "tasks": [
                self._with_assignees(
                    task,
                    assignments_by_task.get(str(task["id"]), []),
                    profiles,
                )
                for task in tasks
            ],
        }

    def join_group(self, user_id: UUID, body: GroupJoinRequest) -> JsonRow:
        group = self.groups.get_group_by_invite_code(body.invite_code)
        if group is None:
            raise ResourceNotFoundError("Invalid invite code.")
        self.groups.add_member(group_id=str(group["id"]), user_id=str(user_id), role="member")
        return {**group, "role": "member"}

    def delete_group(self, user_id: UUID, group_id: UUID) -> None:
        membership = self._require_member(group_id, user_id)
        if membership["role"] != "owner":
            raise PermissionDeniedError("Only the group owner can delete this group.")
        if not self.groups.delete_group(str(group_id), str(user_id)):
            raise ResourceNotFoundError("Group not found.")

    def leave_group(self, user_id: UUID, group_id: UUID) -> None:
        membership = self._require_member(group_id, user_id)
        if membership["role"] == "owner":
            raise PermissionDeniedError("The group owner must delete the group instead.")
        if not self.groups.remove_member(str(group_id), str(user_id)):
            raise ResourceNotFoundError("Group not found.")

    # ── group tasks ─────────────────────────────────────────────────────────
    def create_task(self, user_id: UUID, group_id: UUID, body: GroupTaskCreate) -> JsonRow:
        self._require_member(group_id, user_id)
        data = _serialize_task_fields(body.model_dump())
        assignee_ids = self._assignee_ids(data)
        self._validate_assignees(group_id, assignee_ids)
        data.pop("assigned_to_ids", None)
        data["assigned_to"] = assignee_ids[0] if assignee_ids else None
        data.update({"group_id": str(group_id), "created_by": str(user_id), "status": "pending"})
        task = self.groups.create_task(data)
        self.groups.replace_task_assignees(str(group_id), str(task["id"]), assignee_ids)
        return self._with_assignees(task, assignee_ids)

    def update_task(
        self, user_id: UUID, group_id: UUID, task_id: UUID, body: GroupTaskUpdate
    ) -> JsonRow:
        self._require_member(group_id, user_id)
        data = _serialize_task_fields(body.model_dump(exclude_unset=True))
        if not data:
            existing = self.groups.get_task(str(group_id), str(task_id))
            if existing is None:
                raise ResourceNotFoundError("Task not found.")
            assignee_ids = self._task_assignee_ids(str(group_id), str(task_id), existing)
            return self._with_assignees(existing, assignee_ids)

        assignments_changed = "assigned_to_ids" in data or "assigned_to" in data
        assignee_ids = self._assignee_ids(data) if assignments_changed else []
        if assignments_changed:
            self._validate_assignees(group_id, assignee_ids)
            data["assigned_to"] = assignee_ids[0] if assignee_ids else None
        data.pop("assigned_to_ids", None)
        data["updated_at"] = datetime.now(timezone.utc).isoformat()
        updated = self.groups.update_task(str(group_id), str(task_id), data)
        if updated is None:
            raise ResourceNotFoundError("Task not found.")
        if assignments_changed:
            self.groups.replace_task_assignees(str(group_id), str(task_id), assignee_ids)
        else:
            assignee_ids = self._task_assignee_ids(str(group_id), str(task_id), updated)
        return self._with_assignees(updated, assignee_ids)

    def delete_task(self, user_id: UUID, group_id: UUID, task_id: UUID) -> None:
        self._require_member(group_id, user_id)
        if not self.groups.delete_task(str(group_id), str(task_id)):
            raise ResourceNotFoundError("Task not found.")

    # ── helpers ─────────────────────────────────────────────────────────────
    def _require_member(self, group_id: UUID, user_id: UUID) -> JsonRow:
        membership = self.groups.get_membership(str(group_id), str(user_id))
        if membership is None:
            raise ResourceNotFoundError("Group not found.")
        return membership

    def _validate_assignees(self, group_id: UUID, assignee_ids: list[str]) -> None:
        for assignee_id in assignee_ids:
            if self.groups.get_membership(str(group_id), assignee_id) is None:
                raise DomainValidationError("Every assignee must be a member of this group.")

    @staticmethod
    def _assignee_ids(data: JsonRow) -> list[str]:
        multiple = data.get("assigned_to_ids")
        if multiple:
            return [str(value) for value in multiple]
        single = data.get("assigned_to")
        return [str(single)] if single else []

    def _task_assignee_ids(self, group_id: str, task_id: str, task: JsonRow) -> list[str]:
        rows = self.groups.list_task_assignees(group_id)
        result = [str(row["user_id"]) for row in rows if str(row["task_id"]) == task_id]
        if not result and task.get("assigned_to"):
            result = [str(task["assigned_to"])]
        return result

    def _with_assignees(
        self,
        task: JsonRow,
        assignee_ids: list[str],
        profiles: dict[str, JsonRow] | None = None,
    ) -> JsonRow:
        if profiles is None:
            profiles = self.groups.get_profiles(assignee_ids)
        assignees = [
            {
                "user_id": assignee_id,
                "display_name": profiles.get(assignee_id, {}).get("display_name"),
                "avatar_url": profiles.get(assignee_id, {}).get("avatar_url"),
            }
            for assignee_id in assignee_ids
        ]
        first = assignee_ids[0] if assignee_ids else None
        return {
            **task,
            "assigned_to": first,
            "assignee_name": profiles.get(first, {}).get("display_name") if first else None,
            "assigned_to_ids": assignee_ids,
            "assignees": assignees,
        }

    def _create_group_with_unique_code(self, owner_id: str, name: str) -> JsonRow:
        for attempt in range(1, _INVITE_CODE_ATTEMPTS + 1):
            try:
                return self.groups.create_group(
                    owner_id=owner_id, name=name, invite_code=_generate_invite_code()
                )
            except ResourceConflictError:
                if attempt == _INVITE_CODE_ATTEMPTS:
                    raise
                logger.warning("Invite code collision; retrying (attempt %s)", attempt)
        raise ResourceConflictError("Could not allocate a unique invite code.")

    def _discard_group_safely(self, group_id: str, owner_id: str) -> None:
        try:
            self.groups.delete_group(group_id, owner_id)
        except Exception:
            logger.exception("Could not remove group %s after membership failure", group_id)
