"""XP and levels computed from a user's recorded plan outcomes.

Nothing is stored: XP is derived on every request from each plan's latest
recorded outcome, so correcting or deleting an outcome changes XP immediately
and existing history counts without a backfill.

Rules (also shown to users on the Levels page):
  * Logging any outcome, even "not started", earns LOGGING_XP. Honest records
    are what make the rest of the app useful, so they are always rewarded.
  * Completion XP = (BASE_XP + importance * IMPORTANCE_XP + duration bonus)
    scaled by how much of the plan was done: completed = 100%, partial = its
    completion ratio, not started / abandoned / failed = 0%.
  * The duration bonus is 1 XP per full 15 planned minutes, capped at 8.
  * Reaching level n needs 50 * n * (n - 1) total XP, so each level asks for
    100 XP more than the one before (100, 200, 300, ...).
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation
from typing import Any
from uuid import UUID

from ..repositories.gamification_repository import GamificationRepository

LOGGING_XP = 2
BASE_XP = 10
IMPORTANCE_XP = 2
DEFAULT_IMPORTANCE = 3
DURATION_STEP_MINUTES = 15
MAX_DURATION_BONUS = 8
LEVEL_STEP_XP = 100
WEEK_DAYS = 7
CHART_DAYS = 14
RECENT_LIMIT = 10

LEVEL_TITLES: tuple[tuple[int, str], ...] = (
    (15, "Habit master"),
    (10, "Dedicated"),
    (7, "Focused"),
    (4, "Consistent"),
    (2, "Planner"),
    (1, "Getting started"),
)


@dataclass(frozen=True)
class XpAward:
    outcome: str
    completion_ratio: float
    logging_xp: int
    completion_xp: int

    @property
    def xp(self) -> int:
        return self.logging_xp + self.completion_xp


def _round_half_up(value: float) -> int:
    return int(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _ratio(value: Any) -> float | None:
    if value is None:
        return None
    try:
        ratio = float(Decimal(str(value)))
    except (InvalidOperation, ValueError):
        return None
    return ratio if 0 <= ratio <= 1 else None


def _int_or(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def outcome_of(execution: Mapping[str, Any]) -> tuple[str, float]:
    """Return (outcome, completion ratio) for a finished execution.

    Older rows only have task_status: success counts as fully done, failure as
    nothing done, since their real progress was never recorded.
    """
    outcome = execution.get("outcome_status")
    if execution.get("task_status") == "success":
        return "completed", 1.0
    if outcome == "partial":
        ratio = _ratio(execution.get("completion_ratio"))
        return "partial", ratio if ratio is not None else 0.0
    if outcome in ("not_started", "abandoned"):
        return outcome, 0.0
    return "failed", 0.0


def completion_xp_for(task: Mapping[str, Any]) -> int:
    """Full completion XP for a plan, before scaling by how much was done."""
    importance = min(5, max(1, _int_or(task.get("importance"), DEFAULT_IMPORTANCE)))
    minutes = max(0, _int_or(task.get("planned_duration_min"), 0))
    duration_bonus = min(MAX_DURATION_BONUS, minutes // DURATION_STEP_MINUTES)
    return BASE_XP + importance * IMPORTANCE_XP + duration_bonus


def award_for(task: Mapping[str, Any], execution: Mapping[str, Any]) -> XpAward:
    outcome, ratio = outcome_of(execution)
    return XpAward(
        outcome=outcome,
        completion_ratio=ratio,
        logging_xp=LOGGING_XP,
        completion_xp=_round_half_up(completion_xp_for(task) * ratio),
    )


def level_start_xp(level: int) -> int:
    """Total XP needed to reach `level` (level 1 starts at 0)."""
    return LEVEL_STEP_XP * level * (level - 1) // 2


def level_for_xp(total_xp: int) -> int:
    level = 1
    while level_start_xp(level + 1) <= total_xp:
        level += 1
    return level


def level_title(level: int) -> str:
    for minimum, title in LEVEL_TITLES:
        if level >= minimum:
            return title
    return LEVEL_TITLES[-1][1]


def latest_by_task(executions: Iterable[Mapping[str, Any]]) -> dict[str, Mapping[str, Any]]:
    """Keep each plan's most recent finished execution; corrections replace it."""
    latest: dict[str, Mapping[str, Any]] = {}
    for row in executions:
        task_id = str(row.get("task_id") or "")
        if not task_id or row.get("task_status") is None:
            continue
        key = (str(row.get("created_at") or ""), str(row.get("id") or ""))
        current = latest.get(task_id)
        if current is None or key > (
            str(current.get("created_at") or ""),
            str(current.get("id") or ""),
        ):
            latest[task_id] = row
    return latest


class GamificationService:
    def __init__(self, repository: GamificationRepository) -> None:
        self.repository = repository

    def get_summary(self, user_id: UUID, today: date) -> dict[str, Any]:
        tasks = {str(t["id"]): t for t in self.repository.list_tasks(user_id) if t.get("id")}
        latest = latest_by_task(self.repository.list_finished_executions(user_id))

        events: list[dict[str, Any]] = []
        for task_id, execution in latest.items():
            task = tasks.get(task_id)
            if task is None:
                continue
            award = award_for(task, execution)
            events.append(
                {
                    "task_id": task_id,
                    "title": str(task.get("title") or "Untitled plan"),
                    "task_category": str(task.get("task_category") or "Other"),
                    "planned_date": str(task.get("planned_date") or ""),
                    "outcome": award.outcome,
                    "completion_ratio": round(award.completion_ratio, 3),
                    "logging_xp": award.logging_xp,
                    "completion_xp": award.completion_xp,
                    "xp": award.xp,
                    "_recorded_at": str(execution.get("created_at") or ""),
                }
            )

        total_xp = sum(event["xp"] for event in events)
        level = level_for_xp(total_xp)
        start, next_start = level_start_xp(level), level_start_xp(level + 1)

        by_day: dict[str, int] = {}
        for event in events:
            by_day[event["planned_date"]] = by_day.get(event["planned_date"], 0) + event["xp"]
        week_start = today - timedelta(days=WEEK_DAYS - 1)
        chart_days = [today - timedelta(days=i) for i in range(CHART_DAYS - 1, -1, -1)]

        events.sort(key=lambda e: (e["planned_date"], e["_recorded_at"]), reverse=True)
        recent = [
            {key: value for key, value in event.items() if not key.startswith("_")}
            for event in events[:RECENT_LIMIT]
        ]

        return {
            "total_xp": total_xp,
            "level": level,
            "level_title": level_title(level),
            "level_start_xp": start,
            "next_level_xp": next_start,
            "xp_into_level": total_xp - start,
            "xp_to_next_level": next_start - total_xp,
            "progress": round((total_xp - start) / (next_start - start), 4),
            "xp_this_week": sum(
                xp
                for day, xp in by_day.items()
                if week_start.isoformat() <= day <= today.isoformat()
            ),
            "outcomes_logged": len(events),
            "plans_completed": sum(1 for e in events if e["outcome"] == "completed"),
            "daily_xp": [
                {"date": day.isoformat(), "xp": by_day.get(day.isoformat(), 0)}
                for day in chart_days
            ],
            "recent": recent,
        }
