"""Supabase access for AI plan outcomes."""
from __future__ import annotations

from uuid import UUID

from ..core.errors import RepositoryError
from .base import BaseRepository


class AIOutcomeRepository(BaseRepository):
    table_name = "ai_plan_outcomes"

    def create(self, payload: dict) -> dict:
        response = self._execute(
            self.db.table(self.table_name).insert(payload),
            conflict_detail="This plan already has an outcome.",
        )
        if not response.data:
            raise RepositoryError("The database did not return the created outcome.")
        return response.data[0]

    def get_by_plan(self, plan_input_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table(self.table_name)
            .select("*")
            .eq("plan_input_id", str(plan_input_id))
            .limit(1)
        )
        return response.data[0] if response.data else None

    def get_by_id(self, outcome_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table(self.table_name)
            .select("*")
            .eq("id", str(outcome_id))
            .limit(1)
        )
        return response.data[0] if response.data else None
