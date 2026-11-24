"""Streaks, achievements, and milestones derived from scored plan outcomes.

Everything here is a pure function of the user's plans and their latest
outcomes, so unlocks follow corrections automatically (a badge can be lost
again if the outcome that earned it is changed). Each unlock is dated by the
planned day of the outcome that first met its condition, and its bonus XP is
credited on that day.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

EARLY_BIRD_BEFORE = (9, 0)  # starts before 9:00 AM
NIGHT_OWL_FROM = (20, 0)  # starts at 8:00 PM or later
DEEP_WORK_MINUTES = 120
PERFECT_DAY_MIN_PLANS = 3


@dataclass(frozen=True)
class AchievementDef:
    id: str
    title: str
    description: str
    icon: str
    target: int
    bonus_xp: int
    kind: str = "achievement"  # "achievement" | "streak"


ACHIEVEMENTS: tuple[AchievementDef, ...] = (
    AchievementDef("first_step", "First step", "Complete your first plan.", "✦", 1, 25),
    AchievementDef(
        "early_bird", "Early bird", "Complete 5 plans that start before 9 AM.", "☀", 5, 50
    ),
    AchievementDef(
        "night_owl", "Night owl", "Complete 5 plans that start at 8 PM or later.", "☾", 5, 50
    ),
    AchievementDef(
        "deep_work", "Deep work", "Complete a plan that is 2 hours or longer.", "◆", 1, 25
    ),
    AchievementDef(
        "perfect_day",
        "Perfect day",
        "Complete every plan on a day with at least 3 plans.",
        "✓",
        1,
        50,
    ),
    AchievementDef(
        "explorer", "Explorer", "Complete plans in 5 different categories.", "◎", 5, 50
    ),
    AchievementDef(
        "team_player", "Team player", "Complete 5 plans added from a group task.", "⚑", 5, 50
    ),
    AchievementDef(
        "honest_tracker",
        "Honest tracker",
        "Record 10 outcomes for plans that didn't go as planned.",
        "✎",
        10,
        25,
    ),
    AchievementDef(
        "streak_3", "Warming up", "Complete a plan 3 days in a row.", "▲", 3, 25, "streak"
    ),
    AchievementDef(
        "streak_7", "Week warrior", "Complete a plan 7 days in a row.", "▲", 7, 50, "streak"
    ),
    AchievementDef(
        "streak_30", "Unstoppable", "Complete a plan 30 days in a row.", "▲", 30, 150, "streak"
    ),
)


@dataclass(frozen=True)
class MilestoneTrack:
    id: str
    title: str
    unit: str
    tiers: tuple[tuple[int, int], ...]  # (target, bonus_xp)


MILESTONES: tuple[MilestoneTrack, ...] = (
    MilestoneTrack(
        "plans_completed",
        "Plans completed",
        "plans",
        ((10, 25), (25, 50), (50, 100), (100, 150), (250, 250)),
    ),
    MilestoneTrack(
        "focus_hours",
        "Hours of planned work done",
        "hours",
        ((10, 25), (25, 50), (50, 100), (100, 200)),
    ),
    MilestoneTrack(
        "outcomes_logged",
        "Outcomes recorded",
        "outcomes",
        ((25, 25), (100, 50), (250, 100)),
    ),
)

_TWELVE_HOUR = re.compile(r"^(\d{1,2})(?::(\d{2}))?\s*([AP])\.?M\.?$")
_TWENTY_FOUR_HOUR = re.compile(r"^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$")


def start_time_of(value: Any) -> tuple[int, int] | None:
    """Parse a stored start like "2:00 PM", "7 AM" or "14:30:00"; None if unknown."""
    if not isinstance(value, str):
        return None
    text = value.strip().upper()
    match = _TWELVE_HOUR.match(text)
    if match:
        hour, minute = int(match.group(1)), int(match.group(2) or 0)
        if not 1 <= hour <= 12 or minute > 59:
            return None
        hour = hour % 12 + (12 if match.group(3) == "P" else 0)
        return hour, minute
    match = _TWENTY_FOUR_HOUR.match(text)
    if match:
        hour, minute = int(match.group(1)), int(match.group(2))
        if hour <= 23 and minute <= 59:
            return hour, minute
    return None


def _int_or_zero(value: Any) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0


def _parse_day(value: Any) -> date | None:
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


class _Counter:
    """Counts toward a target and remembers the day the target was first met."""

    def __init__(self, target: int) -> None:
        self.target = target
        self.value: float = 0
        self.reached_on: str | None = None

    def add(self, amount: float, day: str) -> None:
        self.value += amount
        if self.reached_on is None and self.value >= self.target:
            self.reached_on = day


@dataclass(frozen=True)
class Streak:
    current: int
    longest: int
    active_today: bool
    reached: dict[int, str]  # streak length -> day it was first reached


def compute_streak(completed_days: Iterable[str], today: date, lengths: Sequence[int]) -> Streak:
    """A day counts when at least one plan planned for it was completed.

    Today without a completion does not break the streak yet: it stays alive
    until the day ends, so the current streak runs through yesterday.
    """
    days = sorted({d for d in (_parse_day(v) for v in completed_days) if d and d <= today})
    reached: dict[int, str] = {}
    longest = run = 0
    previous: date | None = None
    for day in days:
        run = run + 1 if previous is not None and day - previous == timedelta(days=1) else 1
        previous = day
        longest = max(longest, run)
        for length in lengths:
            if run >= length and length not in reached:
                reached[length] = day.isoformat()
    day_set = set(days)
    active_today = today in day_set
    current = 0
    cursor = today if active_today else today - timedelta(days=1)
    while cursor in day_set:
        current += 1
        cursor -= timedelta(days=1)
    return Streak(current, longest, active_today, reached)


def evaluate_rewards(
    events: Sequence[Mapping[str, Any]],
    tasks: Mapping[str, Mapping[str, Any]],
    today: date,
) -> dict[str, Any]:
    """Return streak, achievements, milestones and the bonus XP credited per day.

    `events` are scored outcomes (one per plan) with task_id, planned_date,
    outcome, completion_ratio and _recorded_at.
    """
    ordered = sorted(events, key=lambda e: (e["planned_date"], e.get("_recorded_at", "")))
    counters = {a.id: _Counter(a.target) for a in ACHIEVEMENTS if a.kind == "achievement"}
    del counters["perfect_day"]  # judged per day below, not counted
    categories: set[str] = set()
    plans_done_days: list[tuple[float, str]] = []
    focus_minutes: list[tuple[float, str]] = []
    logged: list[tuple[float, str]] = []

    for event in ordered:
        day = event["planned_date"]
        task = tasks.get(event["task_id"], {})
        logged.append((1, day))
        if event["outcome"] != "completed":
            counters["honest_tracker"].add(1, day)
            ratio = float(event.get("completion_ratio") or 0)
            if ratio > 0:
                focus_minutes.append((_int_or_zero(task.get("planned_duration_min")) * ratio, day))
            continue
        minutes = _int_or_zero(task.get("planned_duration_min"))
        focus_minutes.append((minutes, day))
        plans_done_days.append((1, day))
        counters["first_step"].add(1, day)
        start = start_time_of(task.get("planned_start_time"))
        if start is not None and start < EARLY_BIRD_BEFORE:
            counters["early_bird"].add(1, day)
        if start is not None and start >= NIGHT_OWL_FROM:
            counters["night_owl"].add(1, day)
        if minutes >= DEEP_WORK_MINUTES:
            counters["deep_work"].add(1, day)
        category = str(task.get("task_category") or "").strip().casefold()
        if category and category not in categories:
            categories.add(category)
            counters["explorer"].add(1, day)
        if task.get("source_group_task_id"):
            counters["team_player"].add(1, day)

    # Perfect day: every plan on the day completed, with enough plans to matter.
    outcome_by_task = {e["task_id"]: e["outcome"] for e in events}
    plans_by_day: dict[str, list[str]] = {}
    for task_id, task in tasks.items():
        day = str(task.get("planned_date") or "")
        if day:
            plans_by_day.setdefault(day, []).append(task_id)
    perfect_days = sorted(
        day
        for day, ids in plans_by_day.items()
        if day <= today.isoformat()
        and len(ids) >= PERFECT_DAY_MIN_PLANS
        and all(outcome_by_task.get(task_id) == "completed" for task_id in ids)
    )

    completed_days = [e["planned_date"] for e in events if e["outcome"] == "completed"]
    streak_lengths = [a.target for a in ACHIEVEMENTS if a.kind == "streak"]
    streak = compute_streak(completed_days, today, streak_lengths)

    bonus_by_day: dict[str, int] = {}

    def unlock(bonus: int, day: str | None) -> None:
        if day is not None:
            bonus_by_day[day] = bonus_by_day.get(day, 0) + bonus

    achievements: list[dict[str, Any]] = []
    for definition in ACHIEVEMENTS:
        if definition.kind == "streak":
            progress = min(streak.longest, definition.target)
            unlocked_on = streak.reached.get(definition.target)
        elif definition.id == "perfect_day":
            unlocked_on = perfect_days[0] if perfect_days else None
            progress = 1 if unlocked_on else 0
        else:
            counter = counters[definition.id]
            progress = int(min(counter.value, definition.target))
            unlocked_on = counter.reached_on
        unlock(definition.bonus_xp, unlocked_on)
        achievements.append(
            {
                "id": definition.id,
                "title": definition.title,
                "description": definition.description,
                "icon": definition.icon,
                "kind": definition.kind,
                "bonus_xp": definition.bonus_xp,
                "target": definition.target,
                "progress": progress,
                "unlocked": unlocked_on is not None,
                "unlocked_on": unlocked_on,
            }
        )

    sources = {
        "plans_completed": (plans_done_days, 1),
        "focus_hours": (focus_minutes, 60),
        "outcomes_logged": (logged, 1),
    }
    milestones: list[dict[str, Any]] = []
    for track in MILESTONES:
        amounts, per_unit = sources[track.id]
        tier_counters = [_Counter(target * per_unit) for target, _ in track.tiers]
        total = 0.0
        for amount, day in amounts:
            total += amount
            for counter in tier_counters:
                counter.add(amount, day)
        tiers = []
        for (target, bonus), counter in zip(track.tiers, tier_counters, strict=True):
            unlock(bonus, counter.reached_on)
            tiers.append(
                {
                    "target": target,
                    "bonus_xp": bonus,
                    "unlocked": counter.reached_on is not None,
                    "unlocked_on": counter.reached_on,
                }
            )
        value = total / per_unit
        milestones.append(
            {
                "id": track.id,
                "title": track.title,
                "unit": track.unit,
                "value": round(value, 1) if per_unit != 1 else int(value),
                "tiers": tiers,
            }
        )

    unlocks = [
        {"title": a["title"], "icon": a["icon"], "bonus_xp": a["bonus_xp"],
         "unlocked_on": a["unlocked_on"]}
        for a in achievements
        if a["unlocked"]
    ] + [
        {"title": f"{m['title']}: {tier['target']} {m['unit']}", "icon": "★",
         "bonus_xp": tier["bonus_xp"], "unlocked_on": tier["unlocked_on"]}
        for m in milestones
        for tier in m["tiers"]
        if tier["unlocked"]
    ]
    unlocks.sort(key=lambda u: u["unlocked_on"], reverse=True)

    return {
        "streak": {
            "current": streak.current,
            "longest": streak.longest,
            "active_today": streak.active_today,
        },
        "achievements": achievements,
        "milestones": milestones,
        "recent_unlocks": unlocks[:3],
        "bonus_by_day": bonus_by_day,
    }
