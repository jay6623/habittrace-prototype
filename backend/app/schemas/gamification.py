"""Response contracts for XP, levels, streaks, achievements and milestones."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel

XpOutcome = Literal["completed", "partial", "not_started", "abandoned", "failed"]


class XpEvent(BaseModel):
    """XP earned by one plan from its latest recorded outcome."""

    task_id: str
    title: str
    task_category: str
    planned_date: str
    outcome: XpOutcome
    completion_ratio: float
    logging_xp: int
    completion_xp: int
    xp: int


class DailyXp(BaseModel):
    date: str  # ISO date, e.g. "2026-11-11"
    xp: int


class StreakInfo(BaseModel):
    current: int
    longest: int
    active_today: bool  # a plan has already been completed today


class Achievement(BaseModel):
    id: str
    title: str
    description: str
    icon: str
    kind: Literal["achievement", "streak"]
    bonus_xp: int
    target: int
    progress: int
    unlocked: bool
    unlocked_on: str | None = None


class MilestoneTier(BaseModel):
    target: int
    bonus_xp: int
    unlocked: bool
    unlocked_on: str | None = None


class Milestone(BaseModel):
    id: str
    title: str
    unit: str
    value: float
    tiers: list[MilestoneTier]


class Unlock(BaseModel):
    title: str
    icon: str
    bonus_xp: int
    unlocked_on: str


class XpSummary(BaseModel):
    total_xp: int
    plan_xp: int
    bonus_xp: int
    level: int
    level_title: str
    level_start_xp: int
    next_level_xp: int
    xp_into_level: int
    xp_to_next_level: int
    progress: float  # 0..1 within the current level
    xp_this_week: int
    outcomes_logged: int
    plans_completed: int
    daily_xp: list[DailyXp]
    recent: list[XpEvent]
    streak: StreakInfo
    badges_unlocked: int
    badges_total: int
    achievements: list[Achievement]
    milestones: list[Milestone]
    recent_unlocks: list[Unlock]
