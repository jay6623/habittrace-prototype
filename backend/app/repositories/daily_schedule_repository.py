"""Supabase persistence for generated daily schedule drafts."""

from __future__ import annotations

from uuid import UUID

from ..core.errors import RepositoryError
from .base import BaseRepository


class DailyScheduleRepository(BaseRepository):
    table_name = "ai_daily_schedules"

    def create(self, payload: dict) -> dict:
        response = self._execute(self.db.table(self.table_name).insert(payload))
        if not response.data:
            raise RepositoryError("The database did not return the daily schedule draft.")
        return response.data[0]

    def get_owned(self, schedule_id: UUID, user_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table(self.table_name)
            .select("*")
            .eq("id", str(schedule_id))
            .eq("user_id", str(user_id))
            .limit(1)
        )
        return response.data[0] if response.data else None

    def update(self, schedule_id: UUID, user_id: UUID, payload: dict) -> dict:
        response = self._execute(
            self.db.table(self.table_name)
            .update(payload)
            .eq("id", str(schedule_id))
            .eq("user_id", str(user_id))
        )
        if not response.data:
            raise RepositoryError("The database did not return the updated daily schedule.")
        return response.data[0]
