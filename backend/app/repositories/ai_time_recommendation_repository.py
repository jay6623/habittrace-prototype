"""Supabase access for time recommendation requests and candidates."""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from ..core.errors import DatabaseUnavailableError, RepositoryError
from .base import BaseRepository

UTC = timezone.utc


class AITimeRecommendationRepository(BaseRepository):
    def create_recommendation(self, payload: dict) -> dict:
        response = self._execute(self.db.table("ai_time_recommendations").insert(payload))
        if not response.data:
            raise RepositoryError("The database did not return the time recommendation.")
        return response.data[0]

    def create_candidates(self, payload: list[dict]) -> list[dict]:
        response = self._execute(self.db.table("ai_time_candidates").insert(payload))
        if len(response.data or []) != len(payload):
            raise RepositoryError("The database did not return all time candidates.")
        return list(response.data)

    def get_recommendation(self, recommendation_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table("ai_time_recommendations")
            .select("*")
            .eq("id", str(recommendation_id))
            .limit(1)
        )
        return response.data[0] if response.data else None

    def get_candidates(self, recommendation_id: UUID) -> list[dict]:
        response = self._execute(
            self.db.table("ai_time_candidates")
            .select("*")
            .eq("recommendation_id", str(recommendation_id))
            .order("rank")
        )
        return list(response.data or [])

    def get_candidate(self, recommendation_id: UUID, candidate_id: UUID) -> dict | None:
        response = self._execute(
            self.db.table("ai_time_candidates")
            .select("*")
            .eq("recommendation_id", str(recommendation_id))
            .eq("id", str(candidate_id))
            .limit(1)
        )
        return response.data[0] if response.data else None

    def select_candidate(
        self,
        recommendation_id: UUID,
        candidate_id: UUID,
        status: str,
    ) -> dict:
        # The selection update is idempotent, so it is safe to retry once when
        # the HTTP connection drops. This also avoids a second read-after-write
        # request, which was the most fragile part of this endpoint.
        decided_at = datetime.now(UTC).isoformat()
        payload = {
            "selected_candidate_id": str(candidate_id),
            "status": status,
            "decided_at": decided_at,
        }
        for attempt in range(2):
            try:
                self._execute(
                    self.db.table("ai_time_recommendations")
                    .update(payload)
                    .eq("id", str(recommendation_id))
                )
                break
            except DatabaseUnavailableError:
                if attempt == 1:
                    raise
        return {
            "id": str(recommendation_id),
            **payload,
        }
