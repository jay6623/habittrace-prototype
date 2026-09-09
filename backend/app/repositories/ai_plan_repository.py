"""Supabase access for immutable AI plan inputs."""

from __future__ import annotations

from uuid import UUID

from ..core.errors import RepositoryError
from .base import BaseRepository


class AIPlanRepository(BaseRepository):
    table_name = "ai_plan_inputs"
    page_size = 1_000

    def create(self, payload: dict) -> dict:
        response = self._execute(
            self.db.table(self.table_name).insert(payload),
            conflict_detail="This plan revision already exists.",
        )
        if not response.data:
            raise RepositoryError("The database did not return the created plan.")
        return response.data[0]

    def get_owned(self, plan_input_id: UUID, user_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table(self.table_name)
            .select("*")
            .eq("id", str(plan_input_id))
            .eq("user_id", str(user_id))
            .limit(1)
        )
        return response.data[0] if response.data else None

    def has_child(self, plan_input_id: UUID) -> bool:
        response = self._execute(
            self.db.table(self.table_name)
            .select("id")
            .eq("parent_plan_input_id", str(plan_input_id))
            .limit(1)
        )
        return bool(response.data)

    def list_schedule_rows(self, user_id: UUID) -> list[dict]:
        rows: list[dict] = []
        offset = 0
        while True:
            response = self._execute(
                self.db.table(self.table_name)
                .select("id,parent_plan_input_id,planned_start,planned_duration_minutes")
                .eq("user_id", str(user_id))
                .order("id")
                .range(offset, offset + self.page_size - 1)
            )
            page = list(response.data or [])
            if not page:
                return rows
            rows.extend(page)
            offset += len(page)
