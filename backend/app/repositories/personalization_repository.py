"""Read-only access to completed personal tasks used for score adjustment."""

from __future__ import annotations

from uuid import UUID

from .base import BaseRepository


class PersonalizationRepository(BaseRepository):
    table_name = "tasks"
    page_size = 1_000

    def list_completed_tasks(self, user_id: UUID) -> list[dict]:
        rows: list[dict] = []
        offset = 0
        while True:
            response = self._execute(
                self.db.table(self.table_name)
                .select(
                    "id,task_category,planned_start_time,planned_date,"
                    "planned_duration_min,task_status,created_at"
                )
                .eq("user_id", str(user_id))
                .in_("task_status", ["success", "failed"])
                .order("created_at", desc=True)
                .range(offset, offset + self.page_size - 1)
            )
            page = list(response.data or [])
            if not page:
                return rows
            rows.extend(page)
            offset += len(page)
