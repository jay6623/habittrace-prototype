"""Execution log CRUD against the Supabase `executions` table."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timezone
from decimal import Decimal
from typing import cast

from postgrest.exceptions import APIError
from supabase import Client

from .execution_ai_sync_service import sync_execution_ai_safely

JsonRow = dict[str, object]


def _rows(data: object) -> list[JsonRow]:
    """Narrow Supabase's broad JSON response type at the table boundary."""
    if not isinstance(data, list) or not all(isinstance(row, dict) for row in data):
        raise RuntimeError("Supabase returned an unexpected table response")
    return cast(list[JsonRow], data)


def _facts(payload: Mapping[str, object]) -> dict:
    data = {key: payload.get(key) for key in (
        "outcome_status", "completion_ratio", "active_minutes",
    )}
    data.update({
        "interruption_count": payload.get("interruption_count", 0),
        "stopped_early": payload.get("stopped_early", False),
        "task_status": payload["task_status"],
        "failure_reason": payload.get("failure_reason"),
    })
    for key, value in data.items():
        if isinstance(value, Decimal):
            data[key] = float(value)
    return data


def _iso(value: object) -> object:
    return value.isoformat() if isinstance(value, datetime) else value


def _validate_actual_data(data: dict, existing: JsonRow) -> None:
    if data.get("outcome_status") in (None, "not_started"):
        return
    start_value = data.get("actual_start_time", existing.get("actual_start_time"))
    end_value = data.get("actual_end_time", existing.get("actual_end_time"))
    if not start_value or not end_value:
        raise ValueError("Actual start and finish times are required for this outcome")
    try:
        start = datetime.fromisoformat(str(start_value).replace("Z", "+00:00"))
        end = datetime.fromisoformat(str(end_value).replace("Z", "+00:00"))
        if start.tzinfo is None or end.tzinfo is None or end < start:
            raise ValueError
    except (ValueError, TypeError) as exc:
        raise ValueError("Provide valid actual start and finish times with UTC offsets") from exc
    if (
        data.get("active_minutes") is not None
        and int(data["active_minutes"]) > int((end - start).total_seconds() // 60)
    ):
        raise ValueError("Active minutes cannot exceed elapsed time")


class ExecutionService:
    def __init__(self, db: Client) -> None:
        self.db = db

    def _get_owned_task(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("tasks")
            .select("*")
            .eq("id", task_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        rows = _rows(result.data)
        return rows[0] if rows else None

    def _sync_legacy_task_status(self, user_id: str, execution: JsonRow) -> None:
        # Migrated databases do this in the execution transaction. A second
        # status write here could overwrite a newer concurrent correction.
        if "ai_outcome_sync_status" not in execution:
            self.db.table("tasks").update({"task_status": execution["task_status"]}).eq(
                "id", execution["task_id"]
            ).eq("user_id", user_id).execute()

    def get_active(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .is_("actual_end_time", "null")
            .is_("task_status", "null")
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

        if "ai_sync_status" in task and not task.get("ai_plan_input_id"):
            from .task_service import TaskService
            TaskService(self.db).update(user_id, task_id, {"ai_sync_status": "pending"})
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
        if existing.get("task_status") is not None:
            # Retry repairs a previous partial write before confirming success.
            self._sync_legacy_task_status(user_id, existing)
            return cast(JsonRow, sync_execution_ai_safely(self.db, existing))

        data = {
            **_facts(payload),
            "actual_end_time": datetime.now(timezone.utc).isoformat(),
        }
        if payload.get("idempotency_key") is not None:
            data["idempotency_key"] = str(payload["idempotency_key"])
        if payload.get("outcome_status") == "not_started":
            raise ValueError("This plan has a recorded start. Record its actual outcome instead.")
        manual_start, manual_end = payload.get("actual_start_time"), payload.get("actual_end_time")
        if isinstance(manual_start, datetime) and isinstance(manual_end, datetime):
            data["actual_start_time"] = manual_start.isoformat()
            data["actual_end_time"] = manual_end.isoformat()
        _validate_actual_data(data, existing)
        result = (
            self.db.table("executions")
            .update(data)
            .eq("id", execution_id)
            .eq("user_id", user_id)
            .is_("task_status", "null")
            .execute()
        )
        result_rows = _rows(result.data)
        if not result_rows:
            return self.complete(user_id, execution_id, payload)

        self._sync_legacy_task_status(user_id, result_rows[0])
        return cast(JsonRow, sync_execution_ai_safely(self.db, result_rows[0]))

    def get_latest_finished(self, user_id: str, task_id: str) -> JsonRow | None:
        result = (
            self.db.table("executions")
            .select("*")
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .not_.is_("task_status", "null")
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
        if existing.get("task_status") is None:
            return self.complete(user_id, execution_id, payload)

        data = _facts(payload)
        if payload.get("outcome_status") == "not_started":
            data.update({"actual_start_time": None, "actual_end_time": None})
        manual_start, manual_end = payload.get("actual_start_time"), payload.get(
            "actual_end_time"
        )
        if isinstance(manual_start, datetime) and isinstance(manual_end, datetime):
            data["actual_start_time"] = manual_start.isoformat()
            data["actual_end_time"] = manual_end.isoformat()

        _validate_actual_data(data, existing)
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

        self._sync_legacy_task_status(user_id, result_rows[0])
        return cast(JsonRow, sync_execution_ai_safely(self.db, result_rows[0]))

    def log(self, user_id: str, payload: Mapping[str, object]) -> JsonRow | None:
        """Complete an active row or insert one finished execution."""
        task_id = str(payload["task_id"])
        if not self._get_owned_task(user_id, task_id):
            return None

        request_key = payload.get("idempotency_key")
        if request_key is not None:
            existing = (
                self.db.table("executions").select("*").eq("user_id", user_id)
                .eq("idempotency_key", str(request_key)).limit(1).execute().data
            )
            if existing:
                if str(existing[0]["task_id"]) != task_id:
                    raise ValueError("Idempotency key belongs to another task")
                return cast(JsonRow, sync_execution_ai_safely(self.db, existing[0]))
        active = self.get_active(user_id, task_id)
        if active:
            return self.complete(user_id, str(active["id"]), payload)

        data = {
            **_facts(payload), "task_id": task_id, "user_id": user_id,
            "actual_start_time": _iso(payload.get("actual_start_time")),
            "actual_end_time": _iso(payload.get("actual_end_time")),
        }
        if request_key is not None:
            data["idempotency_key"] = str(request_key)
        try:
            result = self.db.table("executions").insert(data).execute()
        except APIError as exc:
            if exc.code == "23505" and request_key is not None:
                return self.log(user_id, payload)
            raise

        # Keep the tasks table status in sync
        rows = _rows(result.data)
        if rows:
            self._sync_legacy_task_status(user_id, rows[0])
        return cast(JsonRow, sync_execution_ai_safely(self.db, rows[0])) if rows else None

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
            .is_("task_status", "null")
            .order("created_at", desc=True)
            .execute()
        )
        return _rows(result.data)
