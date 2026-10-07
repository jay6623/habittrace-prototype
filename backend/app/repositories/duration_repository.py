"""Bounded, owner-scoped reads of execution facts and their original plans."""

from uuid import UUID

from .base import BaseRepository


class DurationRepository(BaseRepository):
    def list_observations(self, user_id: UUID) -> list[dict]:
        owner = str(user_id)
        rows = (
            self._execute(
                self.db.table("executions")
                .select(
                    "task_id,ai_plan_input_id,actual_start_time,actual_end_time,outcome_status,task_status"
                )
                .eq("user_id", owner)
                .eq("task_status", "success")
                .eq("outcome_status", "completed")
                .order("created_at", desc=True)
                .limit(500)
            ).data
            or []
        )
        ids = list({r["ai_plan_input_id"] for r in rows if r.get("ai_plan_input_id")})
        snapshots = {}
        for offset in range(0, len(ids), 100):
            page = (
                self._execute(
                    self.db.table("task_ai_sync_jobs")
                    .select("id,payload,created_at")
                    .eq("user_id", owner)
                    .in_("id", ids[offset : offset + 100])
                ).data
                or []
            )
            snapshots.update(
                {r["id"]: {**r["payload"], "captured_at": r["created_at"]} for r in page}
            )
        return [{**r, "plan": snapshots.get(r.get("ai_plan_input_id"))} for r in rows]
