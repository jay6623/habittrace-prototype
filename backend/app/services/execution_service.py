"""Execution log CRUD against the Supabase `executions` table."""
from __future__ import annotations

from typing import Optional

from supabase import Client


class ExecutionService:
    def __init__(self, db: Client) -> None:
        self.db = db

    def log(self, user_id: str, payload: dict) -> dict:
        """Insert an execution record and update the parent task status."""
        data = {
            "task_id": payload["task_id"],
            "user_id": user_id,
            "actual_start_time": payload["actual_start_time"],
            "actual_end_time": payload["actual_end_time"],
            "interruption_count": payload.get("interruption_count", 0),
            "stopped_early": payload.get("stopped_early", False),
            "task_status": payload["task_status"],
            "failure_reason": payload.get("failure_reason"),
        }
        result = self.db.table("executions").insert(data).execute()

        # Keep the tasks table status in sync
        self.db.table("tasks").update(
            {"task_status": payload["task_status"]}
        ).eq("id", payload["task_id"]).eq("user_id", user_id).execute()

        return result.data[0]

    def list_for_user(self, user_id: str) -> list[dict]:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return result.data
