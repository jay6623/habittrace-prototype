"""Execution log CRUD against the Supabase `executions` table."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timezone
from typing import cast

from supabase import Client

JsonRow = dict[str, object]


def _rows(data: object) -> list[JsonRow]:
    """Narrow Supabase's broad JSON response type at the table boundary."""
    if not isinstance(data, list) or not all(isinstance(row, dict) for row in data):
        raise RuntimeError("Supabase returned an unexpected table response")
    return cast(list[JsonRow], data)


class ExecutionService:
    def __init__(self, db: Client) -> None:
        self.db = db

    def _get_owned_task(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("tasks")
            .select("id, task_status")
            .eq("id", task_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        rows = _rows(result.data)
        return rows[0] if rows else None

    def get_active(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .is_("actual_end_time", "null")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = _rows(result.data)
        return rows[0] if rows else None

    def start(self, user_id: str, payload: Mapping[str, object]) -> JsonRow | None:
        """Start one owned task, returning an existing active row idempotently."""
        task_id = str(payload["task_id"])
        task = self._get_owned_task(user_id, task_id)
        if not task:
            return None
        if task.get("task_status") != "pending":
            raise ValueError("Completed tasks cannot be started")

        active = self.get_active(user_id, task_id)
        if active:
            return active

        data = {
            "task_id": task_id,
            "user_id": user_id,
            "actual_start_time": datetime.now(timezone.utc).isoformat(),
            "actual_end_time": None,
            "interruption_count": 0,
            "stopped_early": False,
            "task_status": None,
            "failure_reason": None,
        }
        try:
            result = self.db.table("executions").insert(data).execute()
        except Exception:
            # The partial unique index may win a concurrent Start race. In that
            # case return the row created by the other request; otherwise keep
            # the original database error intact.
            active = self.get_active(user_id, task_id)
            if active:
                return active
            raise
        rows = _rows(result.data)
        return rows[0] if rows else None

    def complete(
        self, user_id: str, execution_id: str, payload: Mapping[str, object]
    ) -> JsonRow | None:
        """Complete an owned active execution and sync its parent task status."""
        existing_result = (
            self.db.table("executions")
            .select("*")
            .eq("id", execution_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        existing_rows = _rows(existing_result.data)
        if not existing_rows:
            return None

        existing = existing_rows[0]
        if existing.get("actual_end_time") is not None:
            # Retry repairs a previous partial write before confirming success.
            self.db.table("tasks").update({"task_status": existing["task_status"]}).eq(
                "id", existing["task_id"]
            ).eq("user_id", user_id).execute()
            return existing

        data = {
            "actual_end_time": datetime.now(timezone.utc).isoformat(),
            "interruption_count": payload.get("interruption_count", 0),
            "stopped_early": payload.get("stopped_early", False),
            "task_status": payload["task_status"],
            "failure_reason": payload.get("failure_reason"),
        }
        manual_start, manual_end = payload.get("actual_start_time"), payload.get("actual_end_time")
        if isinstance(manual_start, datetime) and isinstance(manual_end, datetime):
            data["actual_start_time"] = manual_start.isoformat()
            data["actual_end_time"] = manual_end.isoformat()
        result = (
            self.db.table("executions")
            .update(data)
            .eq("id", execution_id)
            .eq("user_id", user_id)
            .execute()
        )
        result_rows = _rows(result.data)
        if not result_rows:
            return None

        self.db.table("tasks").update({"task_status": payload["task_status"]}).eq(
            "id", existing["task_id"]
        ).eq("user_id", user_id).execute()
        return result_rows[0]

    def get_latest_finished(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .not_.is_("actual_end_time", "null")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        rows = _rows(result.data)
        return rows[0] if rows else None

    def revise(
        self, user_id: str, execution_id: str, payload: Mapping[str, object]
    ) -> JsonRow | None:
        """Update an already-finished owned execution and sync the parent task."""
        existing_result = (
            self.db.table("executions")
            .select("*")
            .eq("id", execution_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        existing_rows = _rows(existing_result.data)
        if not existing_rows:
            return None

        existing = existing_rows[0]
        if existing.get("actual_end_time") is None:
            return self.complete(user_id, execution_id, payload)

        data = {
            "interruption_count": payload.get("interruption_count", 0),
            "stopped_early": payload.get("stopped_early", False),
            "task_status": payload["task_status"],
            "failure_reason": payload.get("failure_reason"),
        }
        manual_start, manual_end = payload.get("actual_start_time"), payload.get(
            "actual_end_time"
        )
        if isinstance(manual_start, datetime) and isinstance(manual_end, datetime):
            data["actual_start_time"] = manual_start.isoformat()
            data["actual_end_time"] = manual_end.isoformat()

        result = (
            self.db.table("executions")
            .update(data)
            .eq("id", execution_id)
            .eq("user_id", user_id)
            .execute()
        )
        result_rows = _rows(result.data)
        if not result_rows:
            return None

        self.db.table("tasks").update({"task_status": payload["task_status"]}).eq(
            "id", existing["task_id"]
        ).eq("user_id", user_id).execute()
        return result_rows[0]

    def log(self, user_id: str, payload: Mapping[str, object]) -> JsonRow | None:
        """Complete an active row or insert one finished execution."""
        task_id = str(payload["task_id"])
        if not self._get_owned_task(user_id, task_id):
            return None

        active = self.get_active(user_id, task_id)
        if active:
            return self.complete(user_id, str(active["id"]), payload)

        data = {
            "task_id": task_id,
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
        self.db.table("tasks").update({"task_status": payload["task_status"]}).eq("id", task_id).eq(
            "user_id", user_id
        ).execute()

        rows = _rows(result.data)
        return rows[0] if rows else None

    def list_for_user(self, user_id: str) -> list[JsonRow]:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        return _rows(result.data)

    def list_active_for_user(self, user_id: str) -> list[JsonRow]:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .is_("actual_end_time", "null")
            .order("created_at", desc=True)
            .execute()
        )
        return _rows(result.data)
