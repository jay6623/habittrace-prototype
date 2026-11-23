"""Owner-scoped reads of plans and recorded outcomes for XP."""

from __future__ import annotations

from typing import Any
from uuid import UUID

from .base import BaseRepository

# PostgREST caps a response (1000 rows by default), so read in stable pages.
PAGE_SIZE = 1000
# Bound one request's work: 20 pages is 20,000 plans or outcomes.
MAX_PAGES = 20

# "*" rather than a column list: source_group_task_id only exists after the
# group personal-planning migration, and naming a missing column fails the query.
TASK_COLUMNS = "*"
EXECUTION_COLUMNS = "id,task_id,task_status,outcome_status,completion_ratio,created_at"


class GamificationRepository(BaseRepository):
    def list_tasks(self, user_id: UUID) -> list[dict[str, Any]]:
        return self._paged("tasks", TASK_COLUMNS, user_id)

    def list_finished_executions(self, user_id: UUID) -> list[dict[str, Any]]:
        rows = self._paged("executions", EXECUTION_COLUMNS, user_id)
        # A running timer has no outcome yet and earns nothing.
        return [row for row in rows if row.get("task_status") is not None]

    def _paged(self, table: str, columns: str, user_id: UUID) -> list[dict[str, Any]]:
        owner = str(user_id)
        rows: list[dict[str, Any]] = []
        for page in range(MAX_PAGES):
            start = page * PAGE_SIZE
            batch = (
                self._execute(
                    self.db.table(table)
                    .select(columns)
                    .eq("user_id", owner)
                    .order("id")
                    .range(start, start + PAGE_SIZE - 1)
                ).data
                or []
            )
            rows.extend(batch)
            if len(batch) < PAGE_SIZE:
                break
        return rows
