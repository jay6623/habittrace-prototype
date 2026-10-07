"""Retry immutable outcome deliveries, atomically including failure reasons."""
from __future__ import annotations

import logging

from supabase import Client

from ..db.supabase_client import get_ai_supabase, is_ai_supabase_configured
from ..repositories.ai_plan_repository import AIPlanRepository
from .task_ai_sync_service import TaskAISyncService

logger = logging.getLogger(__name__)


class ExecutionAISyncService:
    def __init__(self, db: Client, ai_db: Client) -> None:
        self.db, self.ai_db = db, ai_db

    def sync_execution(self, user_id: str, execution_id: str) -> bool:
        jobs = (
            self.db.table("execution_ai_sync_jobs").select("*")
            .eq("user_id", user_id).eq("execution_id", execution_id)
            .eq("status", "pending").order("sequence").limit(100).execute().data
        )
        synced_tasks: set[str] = set()
        for job in jobs:
            if job["task_id"] not in synced_tasks:
                TaskAISyncService(self.db, AIPlanRepository(self.ai_db)).sync_task(
                    user_id, job["task_id"]
                )
                synced_tasks.add(job["task_id"])
            self.ai_db.rpc("deliver_execution_outcome", {
                "p_user_id": user_id,
                "p_plan_input_id": job["plan_input_id"],
                "p_execution_id": execution_id,
                "p_revision": job["sequence"],
                "p_outcome": job["payload"],
                "p_primary_reason": job.get("primary_reason_code"),
            }).execute()
            self.db.table("execution_ai_sync_jobs").update({"status": "synced"}).eq(
                "id", job["id"]
            ).eq("user_id", user_id).execute()
        rows = (
            self.db.table("executions").select("*").eq("id", execution_id)
            .eq("user_id", user_id).limit(1).execute().data
        )
        if not rows or not rows[0].get("ai_outcome_job_id"):
            return False
        latest_id = rows[0]["ai_outcome_job_id"]
        delivered = (
            self.db.table("execution_ai_sync_jobs").select("*").eq("id", latest_id)
            .eq("user_id", user_id).eq("status", "synced").limit(1).execute().data
        )
        if not delivered:
            return False
        eligible = delivered[0]["payload"].get("learning_eligible", True)
        status = "synced" if eligible else "ineligible"
        updated = (
            self.db.table("executions").update({"ai_outcome_sync_status": status})
            .eq("id", execution_id).eq("user_id", user_id)
            .eq("ai_outcome_job_id", latest_id).execute().data
        )
        return bool(updated)


def sync_execution_ai_safely(db: Client, execution: dict) -> dict:
    if execution.get("ai_outcome_sync_status") != "pending" or not is_ai_supabase_configured():
        return execution
    try:
        if ExecutionAISyncService(db, get_ai_supabase()).sync_execution(
            str(execution["user_id"]), str(execution["id"])
        ):
            rows = (
                db.table("executions").select("*").eq("id", execution["id"])
                .eq("user_id", execution["user_id"]).limit(1).execute().data
            )
            if rows:
                return rows[0]
    except Exception as exc:
        logger.warning("AI outcome sync deferred (%s)", type(exc).__name__)
    return execution
