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
        names = self.groups.get_display_names(
            [str(row["user_id"]) for row in members]
            + [str(task["assigned_to"]) for task in tasks if task.get("assigned_to")]
        )
        return {
            "group": {**group, "role": membership["role"]},
            "members": [{**row, "display_name": names.get(str(row["user_id"]))} for row in members],
            "tasks": [self._with_assignee_name(task, names) for task in tasks],
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

    # ── group tasks ─────────────────────────────────────────────────────────
    def create_task(self, user_id: UUID, group_id: UUID, body: GroupTaskCreate) -> JsonRow:
        self._require_member(group_id, user_id)
        data = _serialize_task_fields(body.model_dump())
        if data.get("assigned_to") is not None:
            self._validate_assignee(group_id, str(data["assigned_to"]))
        data.update({"group_id": str(group_id), "created_by": str(user_id), "status": "pending"})
        return self._with_assignee_name(self.groups.create_task(data))

    def update_task(
        self, user_id: UUID, group_id: UUID, task_id: UUID, body: GroupTaskUpdate
    ) -> JsonRow:
        self._require_member(group_id, user_id)
        data = _serialize_task_fields(body.model_dump(exclude_unset=True))
        if not data:
            existing = self.groups.get_task(str(group_id), str(task_id))
            if existing is None:
                raise ResourceNotFoundError("Task not found.")
            return self._with_assignee_name(existing)

        if data.get("assigned_to") is not None:
            self._validate_assignee(group_id, str(data["assigned_to"]))
        data["updated_at"] = datetime.now(timezone.utc).isoformat()
        updated = self.groups.update_task(str(group_id), str(task_id), data)
        if updated is None:
            raise ResourceNotFoundError("Task not found.")
        return self._with_assignee_name(updated)

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

    def _validate_assignee(self, group_id: UUID, assignee_id: str) -> None:
        if self.groups.get_membership(str(group_id), assignee_id) is None:
            raise DomainValidationError("Assignee must be a member of this group.")

    def _with_assignee_name(
        self, task: JsonRow, names: dict[str, str | None] | None = None
    ) -> JsonRow:
        assignee = task.get("assigned_to")
        if not assignee:
            return {**task, "assignee_name": None}
        if names is None:
            names = self.groups.get_display_names([str(assignee)])
        return {**task, "assignee_name": names.get(str(assignee))}

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
