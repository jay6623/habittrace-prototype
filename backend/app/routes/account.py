"""User-owned, paginated export. Never exports service credentials or other users."""

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId

router = APIRouter()


def export_rows(db, table: str, user_id: str) -> list[dict]:
    rows = []
    offset = 0
    while True:
        batch = (
            db.table(table)
            .select("*")
            .eq("user_id", user_id)
            .order("id")
            .range(offset, offset + 499)
            .execute()
            .data
        )
        rows.extend(batch)
        if len(batch) < 500:
            return rows
        offset += 500


@router.get("/export")
def export_account(user_id: CurrentUserId):
    if not is_supabase_configured():
        raise HTTPException(status_code=503, detail="Records are temporarily unavailable.")
    try:
        db = get_supabase()
        return {
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "scope": "personal_tasks_and_executions",
            "tasks": export_rows(db, "tasks", str(user_id)),
            "executions": export_rows(db, "executions", str(user_id)),
        }
    except Exception as exc:
        raise HTTPException(
            status_code=503, detail="Could not export your records. Try again."
        ) from exc
