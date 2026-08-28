"""Persistence for coach conversations, messages, and confirmed actions."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from supabase import Client


class CoachRepository:
    def __init__(self, db: Client) -> None:
        self.db = db

    def create_conversation(self, user_id: str) -> dict:
        result = (
            self.db.table("coach_conversations")
            .insert(
                {
                    "user_id": user_id,
                    "title": "AI coaching conversation",
                }
            )
            .execute()
        )
        return result.data[0]

    def get_owned_conversation(self, conversation_id: UUID, user_id: str) -> dict | None:
        result = (
            self.db.table("coach_conversations")
            .select("*")
            .eq("id", str(conversation_id))
            .eq("user_id", user_id)
            .eq("status", "active")
            .limit(1)
            .execute()
        )
        return result.data[0] if result.data else None

    def latest_conversation(self, user_id: str) -> dict | None:
        result = (
            self.db.table("coach_conversations")
            .select("*")
            .eq("user_id", user_id)
            .eq("status", "active")
            .order("updated_at", desc=True)
            .limit(1)
            .execute()
        )
        return result.data[0] if result.data else None

    def add_message(self, conversation_id: str, user_id: str, role: str, content: str) -> dict:
        result = (
            self.db.table("coach_messages")
            .insert(
                {
                    "conversation_id": conversation_id,
                    "user_id": user_id,
                    "role": role,
                    "content": content,
                }
            )
            .execute()
        )
        self.db.table("coach_conversations").update(
            {
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        ).eq("id", conversation_id).eq("user_id", user_id).execute()
        return result.data[0]

    def list_messages(self, conversation_id: str, user_id: str, limit: int = 30) -> list[dict]:
        result = (
            self.db.table("coach_messages")
            .select("id,role,content,created_at")
            .eq("conversation_id", conversation_id)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return list(reversed(result.data or []))

    def list_pending_proposals(self, conversation_id: str, user_id: str) -> list[dict]:
        result = (
            self.db.table("agent_action_proposals")
            .select("id,payload,expires_at,created_at")
            .eq("conversation_id", conversation_id)
            .eq("user_id", user_id)
            .eq("status", "pending")
            .gt("expires_at", datetime.now(timezone.utc).isoformat())
            .order("created_at")
            .execute()
        )
        return [{"id": row["id"], **(row.get("payload") or {})} for row in (result.data or [])]

    def archive_conversation(self, conversation_id: UUID, user_id: str) -> bool:
        result = (
            self.db.table("coach_conversations")
            .update({"status": "archived", "updated_at": datetime.now(timezone.utc).isoformat()})
            .eq("id", str(conversation_id))
            .eq("user_id", user_id)
            .execute()
        )
        return bool(result.data)

    def create_proposal(self, user_id: str, conversation_id: str | None, payload: dict) -> dict:
        result = (
            self.db.table("agent_action_proposals")
            .insert(
                {
                    "id": str(uuid4()),
                    "user_id": user_id,
                    "conversation_id": conversation_id,
                    "action_type": "create_task",
                    "payload": payload,
                    "status": "pending",
                    "expires_at": (datetime.now(timezone.utc) + timedelta(hours=24)).isoformat(),
                }
            )
            .execute()
        )
        return result.data[0]

    def get_owned_proposal(self, proposal_id: UUID, user_id: str) -> dict | None:
        result = (
            self.db.table("agent_action_proposals")
            .select("*")
            .eq("id", str(proposal_id))
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        return result.data[0] if result.data else None

    def finish_proposal(
        self, proposal_id: UUID, user_id: str, status: str, result_payload: dict | None = None
    ) -> dict:
        result = (
            self.db.table("agent_action_proposals")
            .update(
                {
                    "status": status,
                    "result": result_payload,
                    "resolved_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            .eq("id", str(proposal_id))
            .eq("user_id", user_id)
            .execute()
        )
        return result.data[0]
