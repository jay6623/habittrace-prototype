"""
AI Coach chat service — streams responses from Ollama (Phi-3 by default).

Requirements:
  1. Install Ollama: https://ollama.com
  2. Pull the model:  ollama pull phi3
  3. Set OLLAMA_CHAT_URL / OLLAMA_MODEL in backend/.env if not using localhost defaults
"""
from __future__ import annotations

import json
import logging
import re
from datetime import date
from typing import AsyncGenerator, Optional

import httpx

from ..config import settings

logger = logging.getLogger(__name__)
MAX_HISTORY  = 6   # keep last N message pairs in context

TASK_TAG_RE = re.compile(r"\[TASK\](.*?)\[/TASK\]", re.DOTALL)


class ChatService:
    def __init__(self, db=None) -> None:
        self.db = db

    # ── Build user context from analytics ────────────────────────────────
    def _get_user_context(self, user_id: str) -> str:
        if not self.db:
            return ""
        try:
            from .analytics_service import AnalyticsService

            svc     = AnalyticsService(self.db)
            summary = svc.get_summary(user_id, period="week")
            today   = date.today().isoformat()

            today_tasks: list[dict] = (
                self.db.table("tasks")
                .select("*")
                .eq("user_id", user_id)
                .eq("planned_date", today)
                .execute()
            ).data

            pending = [t for t in today_tasks if t.get("task_status") == "pending"]
            done    = [t for t in today_tasks if t.get("task_status") == "success"]
            failed  = [t for t in today_tasks if t.get("task_status") == "failed"]

            lines = [
                f"- This week: {summary['success_rate']}% success rate ({summary['total_tasks']} tasks tracked)",
                f"- Best time of day: {summary['best_time_of_day']}",
                f"- Most failed category: {summary['most_failed_category']}",
                f"- Avg interruptions per task: {summary['avg_interruptions']}",
                f"- Today: {len(done)} done, {len(pending)} pending, {len(failed)} failed",
            ]

            if pending:
                titles = ", ".join(t["title"] for t in pending[:4])
                lines.append(f"- Pending today: {titles}")

            if summary.get("failure_by_reason"):
                top = sorted(
                    summary["failure_by_reason"].items(), key=lambda x: -x[1]
                )[:3]
                reasons = ", ".join(
                    f"{k.replace('_', ' ')} ({v}×)" for k, v in top
                )
                lines.append(f"- Top failure reasons this week: {reasons}")

            return "\n".join(lines)
        except Exception as exc:
            logger.warning("Could not build user context: %s", exc)
            return ""

    # ── Stream chat tokens from Ollama ────────────────────────────────────
    async def stream(
        self,
        user_id: str,
        message: str,
        history: list[dict],
    ) -> AsyncGenerator[str, None]:

        user_context = self._get_user_context(user_id)
        today_str    = date.today().isoformat()

        system_prompt = (
            "You are HabitTrace AI Coach, a concise and supportive productivity coach.\n"
            "You have access to the user's real habit-tracking data shown below.\n"
            "Keep every reply to 2–4 sentences. Be specific — reference the user's actual numbers when helpful.\n"
            "Always reply in English.\n\n"
            f"Today's date: {today_str}\n\n"
            "=== TASK SCHEDULING ===\n"
            "If the user wants to schedule or add a task (e.g. 'I will study at 9 PM', 'schedule a workout tomorrow at 6pm',\n"
            "'I'm going to read at 2:00 p.m. on March 25.'), do the following:\n"
            "1. Write a short friendly confirmation message (1–2 sentences).\n"
            "2. If date or time is completely missing and cannot be inferred, ask ONE clarifying question instead.\n"
            "3. Otherwise, append this EXACT tag at the very end (no text after it):\n"
            "[TASK]{\"title\":\"<task title>\",\"planned_date\":\"<YYYY-MM-DD>\","
            "\"planned_start_time\":\"<HH:MM>\",\"task_category\":\"<Study|Work|Exercise|Personal|Other>\","
            "\"planned_duration_min\":<number>,\"importance\":3,\"energy_level\":3,"
            "\"focus_level\":3,\"total_tasks_today\":1}[/TASK]\n\n"
            "Rules for the JSON:\n"
            "- planned_date: YYYY-MM-DD. Use today's date if not specified.\n"
            "- planned_start_time: 24-hour HH:MM (e.g. 09:00, 14:30).\n"
            "- task_category: pick closest — Study, Work, Exercise, Personal, Other.\n"
            "- planned_duration_min: infer from context; default 60.\n"
            "- importance/energy_level/focus_level: always 3 (default).\n"
            "- Do NOT add any text after [/TASK].\n\n"
            "If it is NOT a scheduling request, respond normally with NO [TASK] tag.\n\n"
            "=== User's HabitTrace data ===\n"
            + (user_context if user_context else "(no data yet — user hasn't tracked tasks)")
        )

        messages = [{"role": "system", "content": system_prompt}]
        for msg in history[-MAX_HISTORY:]:
            messages.append({"role": msg["role"], "content": msg["content"]})
        messages.append({"role": "user", "content": message})

        payload = {
            "model":    settings.ollama_model,
            "messages": messages,
            "stream":   True,
            "options":  {"temperature": 0.7, "num_predict": 400},
        }

        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                async with client.stream(
                    "POST", settings.ollama_chat_url, json=payload
                ) as resp:
                    if resp.status_code != 200:
                        yield _sse_error(
                            "Ollama returned an error. "
                            "Make sure Ollama is running and `phi3` model is installed "
                            "(run: ollama pull phi3)."
                        )
                        return

                    full_text = ""

                    async for line in resp.aiter_lines():
                        if not line:
                            continue
                        try:
                            chunk = json.loads(line)
                            token = chunk.get("message", {}).get("content", "")
                            if token:
                                full_text += token
                                # Stream all tokens — frontend strips [TASK] block
                                yield f"data: {json.dumps({'token': token})}\n\n"

                            if chunk.get("done"):
                                # Extract task JSON from full response if present
                                match = TASK_TAG_RE.search(full_text)
                                if match:
                                    try:
                                        task_data = json.loads(match.group(1).strip())
                                        yield f"data: {json.dumps({'task_candidate': task_data})}\n\n"
                                    except json.JSONDecodeError as e:
                                        logger.warning("Could not parse task JSON: %s", e)

                                yield "data: [DONE]\n\n"
                                return
                        except json.JSONDecodeError:
                            continue

        except httpx.ConnectError:
            yield _sse_error(
                "Cannot connect to Ollama. "
                "Please start Ollama (open the Ollama app) and run: ollama pull phi3"
            )
        except httpx.TimeoutException:
            yield _sse_error("Ollama response timed out. The model may still be loading — try again.")
        except Exception as exc:
            logger.exception("Unexpected chat error: %s", exc)
            yield _sse_error(f"Unexpected error: {exc}")


def _sse_error(msg: str) -> str:
    return f"data: {json.dumps({'error': msg})}\n\ndata: [DONE]\n\n"
