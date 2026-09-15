"""Supabase access for groups, memberships, and shared group tasks."""

from __future__ import annotations

from typing import Any

from ..core.errors import RepositoryError
from .base import BaseRepository

JsonRow = dict[str, Any]


class GroupRepository(BaseRepository):
    groups_table = "groups"
    members_table = "group_members"
    tasks_table = "group_tasks"
    assignees_table = "group_task_assignees"
    profiles_table = "profiles"

    # ── groups ──────────────────────────────────────────────────────────────
    def create_group(self, *, owner_id: str, name: str, invite_code: str) -> JsonRow:
        response = self._execute(
            self.db.table(self.groups_table).insert(
                {"owner_id": owner_id, "name": name, "invite_code": invite_code}
            ),
            conflict_detail="The invite code is already in use.",
            validation_detail="The group data violates a database constraint.",
        )
        if not response.data:
            raise RepositoryError("The database did not return the created group.")
        return response.data[0]

    def get_group(self, group_id: str) -> JsonRow | None:
        response = self._execute(
            self.db.table(self.groups_table).select("*").eq("id", group_id).limit(1)
        )
        return response.data[0] if response.data else None

    def get_group_by_invite_code(self, invite_code: str) -> JsonRow | None:
        response = self._execute(
            self.db.table(self.groups_table).select("*").eq("invite_code", invite_code).limit(1)
        )
        return response.data[0] if response.data else None

    def list_groups_by_ids(self, group_ids: list[str]) -> list[JsonRow]:
        if not group_ids:
            return []
        response = self._execute(self.db.table(self.groups_table).select("*").in_("id", group_ids))
        return list(response.data or [])

    def delete_group(self, group_id: str, owner_id: str) -> bool:
        response = self._execute(
            self.db.table(self.groups_table).delete().eq("id", group_id).eq("owner_id", owner_id)
        )
        return bool(response.data)

    # ── memberships ─────────────────────────────────────────────────────────
    def add_member(self, *, group_id: str, user_id: str, role: str) -> JsonRow:
        response = self._execute(
            self.db.table(self.members_table).insert(
                {"group_id": group_id, "user_id": user_id, "role": role}
            ),
            conflict_detail="You are already a member of this group.",
            validation_detail="The membership violates a database constraint.",
        )
        if not response.data:
            raise RepositoryError("The database did not return the created membership.")
        return response.data[0]

    def get_membership(self, group_id: str, user_id: str) -> JsonRow | None:
        response = self._execute(
            self.db.table(self.members_table)
            .select("*")
            .eq("group_id", group_id)
            .eq("user_id", user_id)
            .limit(1)
        )
        return response.data[0] if response.data else None

    def list_memberships_for_user(self, user_id: str) -> list[JsonRow]:
        response = self._execute(
            self.db.table(self.members_table).select("*").eq("user_id", user_id)
        )
        return list(response.data or [])

    def list_members(self, group_id: str) -> list[JsonRow]:
        response = self._execute(
            self.db.table(self.members_table)
            .select("*")
            .eq("group_id", group_id)
            .order("joined_at")
        )
        return list(response.data or [])

    def remove_member(self, group_id: str, user_id: str) -> bool:
        response = self._execute(
            self.db.table(self.members_table)
            .delete()
            .eq("group_id", group_id)
            .eq("user_id", user_id)
        )
        return bool(response.data)

    def get_display_names(self, user_ids: list[str]) -> dict[str, str | None]:
        """Return display names from `profiles`; only id and display_name are read."""
        unique_ids = sorted(set(user_ids))
        if not unique_ids:
            return {}
        response = self._execute(
            self.db.table(self.profiles_table).select("id, display_name").in_("id", unique_ids)
        )
        return {
            str(row["id"]): row.get("display_name")
            for row in response.data or []
            if row.get("id") is not None
        }

    # ── group tasks ─────────────────────────────────────────────────────────
    def create_task(self, data: JsonRow) -> JsonRow:
        response = self._execute(
            self.db.table(self.tasks_table).insert(data),
            validation_detail="The task data violates a database constraint.",
        )
        if not response.data:
            raise RepositoryError("The database did not return the created task.")
        return response.data[0]

    def list_tasks(self, group_id: str) -> list[JsonRow]:
        response = self._execute(
            self.db.table(self.tasks_table)
            .select("*")
            .eq("group_id", group_id)
            .order("created_at", desc=True)
        )
        return list(response.data or [])

    def get_task(self, group_id: str, task_id: str) -> JsonRow | None:
        response = self._execute(
            self.db.table(self.tasks_table)
            .select("*")
            .eq("group_id", group_id)
            .eq("id", task_id)
            .limit(1)
        )
        return response.data[0] if response.data else None

    def update_task(self, group_id: str, task_id: str, data: JsonRow) -> JsonRow | None:
        response = self._execute(
            self.db.table(self.tasks_table).update(data).eq("group_id", group_id).eq("id", task_id),
            validation_detail="The task data violates a database constraint.",
        )
        return response.data[0] if response.data else None

    def delete_task(self, group_id: str, task_id: str) -> bool:
        response = self._execute(
            self.db.table(self.tasks_table).delete().eq("group_id", group_id).eq("id", task_id)
        )
        return bool(response.data)

    def list_task_assignees(self, group_id: str) -> list[JsonRow]:
        response = self._execute(
            self.db.table(self.assignees_table).select("*").eq("group_id", group_id)
        )
        return list(response.data or [])

    def replace_task_assignees(
        self, group_id: str, task_id: str, user_ids: list[str]
    ) -> None:
        self._execute(
            self.db.table(self.assignees_table)
            .delete()
            .eq("group_id", group_id)
            .eq("task_id", task_id)
        )
        if user_ids:
            for user_id in user_ids:
                self._execute(
                    self.db.table(self.assignees_table).insert(
                        {"group_id": group_id, "task_id": task_id, "user_id": user_id}
                    ),
                    validation_detail="The task assignees violate a database constraint.",
                )
