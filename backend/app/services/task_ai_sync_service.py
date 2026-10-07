"""Deliver primary-DB outbox snapshots to the separate AI DB idempotently."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from uuid import UUID

from supabase import Client

from ..core.errors import ResourceConflictError
from ..db.supabase_client import get_ai_supabase, is_ai_supabase_configured
from ..repositories.ai_plan_repository import AIPlanRepository

logger = logging.getLogger(__name__)


class TaskAISyncService:
    def __init__(self, db: Client, plans: AIPlanRepository) -> None:
        self.db = db
        self.plans = plans

    def sync_task(self, user_id: str, task_id: str) -> bool:
        # Parents must be delivered before children. A bounded batch allows a
        # later read/retry to continue long histories without unbounded work.
        jobs = (
            self.db.table("task_ai_sync_jobs").select("*")
            .eq("user_id", user_id).eq("task_id", task_id).eq("status", "pending")
            .order("sequence").limit(100).execute().data
        )
        for job in jobs:
            plan_id = UUID(job["id"])
            owner = UUID(user_id)
            if self.plans.get_owned(plan_id, owner) is None:
                try:
                    self.plans.create(job["payload"])
                except ResourceConflictError:
                    # Another request may have delivered the same job, or the
                    # insert may have committed before its response was lost.
                    if self.plans.get_owned(plan_id, owner) is None:
                        raise
            self.db.table("task_ai_sync_jobs").update({
                "status": "synced",
                "synced_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", job["id"]).eq("user_id", user_id).execute()
        rows = (
            self.db.table("tasks").select("*")
            .eq("id", task_id).eq("user_id", user_id).limit(1).execute().data
        )
        if not rows:
            return False
        task = rows[0]
        # Reconcile even when an earlier attempt delivered the job but failed
        # to acknowledge the task. A conditional update protects newer edits.
        delivered = (
            self.db.table("task_ai_sync_jobs").select("id")
            .eq("id", task.get("ai_plan_input_id")).eq("user_id", user_id)
            .eq("status", "synced").limit(1).execute().data
        )
        if delivered:
            updated = (
                self.db.table("tasks").update({"ai_sync_status": "synced"})
                .eq("id", task_id).eq("user_id", user_id)
                .eq("ai_plan_input_id", task["ai_plan_input_id"]).execute().data
            )
            return bool(updated)
        return False


def sync_task_ai_safely(db: Client, task: dict) -> dict:
    """AI outages leave a durable pending job and do not undo a saved task."""
    if task.get("ai_sync_status") != "pending" or not is_ai_supabase_configured():
        return task
    try:
        service = TaskAISyncService(db, AIPlanRepository(get_ai_supabase()))
        if service.sync_task(str(task["user_id"]), str(task["id"])):
            rows = (
                db.table("tasks").select("*").eq("id", task["id"])
                .eq("user_id", task["user_id"]).limit(1).execute().data
            )
            if rows:
                return rows[0]
    except Exception as exc:
        # Do not log payloads, notes, credentials, or remote error bodies.
        logger.warning("AI task sync deferred (%s)", type(exc).__name__)
    return task
