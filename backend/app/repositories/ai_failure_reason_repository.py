"""Supabase access for failure reason definitions and assignments."""

from __future__ import annotations

from uuid import UUID

from .base import BaseRepository


class AIFailureReasonRepository(BaseRepository):
    definitions_table = "ai_failure_reason_definitions"
    assignments_table = "ai_outcome_failure_reasons"

    def list_active_definitions(self) -> list[dict]:
        response = self._execute(
            self.db.table(self.definitions_table)
            .select("code,display_name,description,is_active")
            .eq("is_active", True)
            .order("code")
        )
        return list(response.data or [])

    def find_active_codes(self, reason_codes: list[str]) -> set[str]:
        if not reason_codes:
            return set()
        response = self._execute(
            self.db.table(self.definitions_table)
            .select("code")
            .eq("is_active", True)
            .in_("code", reason_codes)
        )
        return {row["code"] for row in response.data or []}

    def list_for_outcome(self, outcome_id: UUID) -> list[dict]:
        response = self._execute(
            self.db.table(self.assignments_table).select("*").eq("outcome_id", str(outcome_id))
        )
        return list(response.data or [])

    def create_many(self, payload: list[dict]) -> list[dict]:
        response = self._execute(
            self.db.table(self.assignments_table).insert(payload),
            conflict_detail="Failure reasons have already been recorded for this outcome.",
            validation_detail="One or more failure reason codes are invalid.",
        )
        return list(response.data or [])
