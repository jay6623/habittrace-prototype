"""Task CRUD against the Supabase `tasks` table."""

from __future__ import annotations

from datetime import date

from supabase import Client


class TaskService:
    def __init__(self, db: Client) -> None:
        self.db = db

    # ── Create ──────────────────────────────────────────────────────────
    def create(self, user_id: str, payload: dict) -> dict:
        data = {
            "user_id": user_id,
            "title": payload["title"],
            "notes": payload.get("notes"),
            "task_category": payload["task_category"],
            "planned_start_time": payload["planned_start_time"],
            "planned_date": payload.get("planned_date") or date.today().isoformat(),
            "planned_duration_min": payload["planned_duration_min"],
            "importance": payload["importance"],
            "energy_level": payload["energy_level"],
            "focus_level": payload["focus_level"],
            "total_tasks_today": payload["total_tasks_today"],
            "task_status": "pending",
        }
        result = self.db.table("tasks").insert(data).execute()
        return result.data[0]

    # ── Read ────────────────────────────────────────────────────────────
    def list_for_user(self, user_id: str, date_filter: str | None = None) -> list[dict]:
        query = self.db.table("tasks").select("*").eq("user_id", user_id)
        if date_filter:
            query = query.eq("planned_date", date_filter)
        result = query.order("planned_start_time").execute()
        return result.data

    def get(self, user_id: str, task_id: str) -> dict | None:
        result = (
            self.db.table("tasks").select("*").eq("id", task_id).eq("user_id", user_id).execute()
        )
        return result.data[0] if result.data else None

    # ── Update ──────────────────────────────────────────────────────────
    def update(self, user_id: str, task_id: str, payload: dict) -> dict | None:
        if not payload:
            return self.get(user_id, task_id)
        result = (
            self.db.table("tasks").update(payload).eq("id", task_id).eq("user_id", user_id).execute()
        )
        return result.data[0] if result.data else None

    def update_status(self, user_id: str, task_id: str, status: str) -> dict | None:
        result = (
            self.db.table("tasks")
            .update({"task_status": status})
            .eq("id", task_id)
            .eq("user_id", user_id)
            .execute()
        )
        return result.data[0] if result.data else None

    # ── Delete ──────────────────────────────────────────────────────────
    def delete(self, user_id: str, task_id: str) -> bool:
        result = self.db.table("tasks").delete().eq("id", task_id).eq("user_id", user_id).execute()
        return len(result.data) > 0
