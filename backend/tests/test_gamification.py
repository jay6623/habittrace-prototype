from datetime import date
from uuid import uuid4

import pytest

from app.dependencies.database import get_primary_database
from app.main import app
from app.repositories import gamification_repository
from app.repositories.gamification_repository import GamificationRepository
from app.services.gamification_service import (
    GamificationService,
    award_for,
    completion_xp_for,
    latest_by_task,
    level_for_xp,
    level_start_xp,
    level_title,
)

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

TODAY = date(2026, 11, 11)
OWNER = str(USER_ID)


def task(**updates):
    row = {
        "id": str(uuid4()),
        "user_id": OWNER,
        "title": "Read chapter",
        "task_category": "Study",
        "planned_date": TODAY.isoformat(),
        "planned_duration_min": 60,
        "importance": 3,
    }
    row.update(updates)
    return row


def execution(task_row, **updates):
    row = {
        "id": str(uuid4()),
        "task_id": task_row["id"],
        "user_id": task_row["user_id"],
        "task_status": "success",
        "outcome_status": "completed",
        "completion_ratio": 1,
        "created_at": "2026-11-11T18:00:00+00:00",
    }
    row.update(updates)
    return row


def summary(tasks, executions):
    db = MemoryDatabase({"tasks": tasks, "executions": executions})
    return GamificationService(GamificationRepository(db)).get_summary(USER_ID, TODAY)


# ── XP rules ────────────────────────────────────────────────────────────────


def test_completion_xp_uses_importance_and_capped_duration_bonus():
    assert completion_xp_for(task(importance=3, planned_duration_min=60)) == 10 + 6 + 4
    assert completion_xp_for(task(importance=5, planned_duration_min=600)) == 10 + 10 + 8
    assert completion_xp_for(task(importance=1, planned_duration_min=10)) == 10 + 2 + 0
    # Missing or invalid values fall back to safe defaults instead of failing.
    assert completion_xp_for(task(importance=None, planned_duration_min=None)) == 16
    assert completion_xp_for(task(importance=99, planned_duration_min=-5)) == 20


@pytest.mark.parametrize(
    "facts,outcome,expected_xp",
    [
        ({"task_status": "success", "outcome_status": "completed"}, "completed", 2 + 20),
        (
            {"task_status": "failed", "outcome_status": "partial", "completion_ratio": "0.5"},
            "partial",
            2 + 10,
        ),
        (
            {"task_status": "failed", "outcome_status": "not_started", "completion_ratio": 0},
            "not_started",
            2,
        ),
        (
            {"task_status": "failed", "outcome_status": "abandoned", "completion_ratio": 0},
            "abandoned",
            2,
        ),
        # Legacy rows recorded before outcome_status existed.
        ({"task_status": "success", "outcome_status": None}, "completed", 22),
        ({"task_status": "failed", "outcome_status": None}, "failed", 2),
    ],
)
def test_every_logged_outcome_earns_logging_xp_and_progress_scales_completion(
    facts, outcome, expected_xp
):
    plan = task()
    award = award_for(plan, execution(plan, **facts))
    assert award.outcome == outcome
    assert award.logging_xp == 2
    assert award.xp == expected_xp


def test_partial_xp_rounds_half_up_and_ignores_bad_ratios():
    plan = task(importance=3, planned_duration_min=75)  # 10 + 6 + 5 = 21 full XP
    half = award_for(plan, execution(plan, task_status="failed", outcome_status="partial",
                                     completion_ratio=0.5))
    assert half.completion_xp == 11
    bad = award_for(plan, execution(plan, task_status="failed", outcome_status="partial",
                                    completion_ratio="not-a-number"))
    assert bad.completion_xp == 0


def test_level_thresholds_grow_by_one_hundred_each_level():
    assert [level_start_xp(n) for n in range(1, 6)] == [0, 100, 300, 600, 1000]
    assert level_for_xp(0) == 1
    assert level_for_xp(99) == 1
    assert level_for_xp(100) == 2
    assert level_for_xp(299) == 2
    assert level_for_xp(300) == 3
    assert level_for_xp(1000) == 5
    assert level_title(1) == "Getting started"
    assert level_title(5) == "Consistent"
    assert level_title(40) == "Habit master"


def test_latest_execution_per_plan_wins_so_corrections_replace_old_results():
    plan = task()
    old = execution(plan, created_at="2026-11-10T08:00:00+00:00")
    new = execution(
        plan,
        task_status="failed",
        outcome_status="not_started",
        completion_ratio=0,
        created_at="2026-11-10T09:00:00+00:00",
    )
    running = execution(plan, task_status=None, created_at="2026-11-11T09:00:00+00:00")
    assert latest_by_task([new, old, running])[plan["id"]]["id"] == new["id"]


# ── Summary ─────────────────────────────────────────────────────────────────


def test_summary_totals_levels_week_window_and_recent_order():
    done = task(title="Done", planned_date="2026-11-10")
    half = task(title="Half", planned_date="2026-11-11")
    skipped = task(title="Skipped", planned_date="2026-11-04")  # 7 days ago: outside week
    pending = task(title="Pending")  # no outcome yet: no XP
    result = summary(
        [done, half, skipped, pending],
        [
            execution(done),
            execution(half, task_status="failed", outcome_status="partial",
                      completion_ratio=0.5),
            execution(skipped, task_status="failed", outcome_status="not_started",
                      completion_ratio=0),
        ],
    )
    assert result["total_xp"] == 22 + 12 + 2
    assert result["xp_this_week"] == 22 + 12
    assert result["outcomes_logged"] == 3
    assert result["plans_completed"] == 1
    assert result["level"] == 1
    assert result["level_start_xp"] == 0
    assert result["next_level_xp"] == 100
    assert result["xp_into_level"] == 36
    assert result["xp_to_next_level"] == 64
    assert result["progress"] == 0.36
    assert [e["title"] for e in result["recent"]] == ["Half", "Done", "Skipped"]
    assert len(result["daily_xp"]) == 14
    assert result["daily_xp"][-1] == {"date": "2026-11-11", "xp": 12}
    assert result["daily_xp"][-2] == {"date": "2026-11-10", "xp": 22}
    assert all(not key.startswith("_") for key in result["recent"][0])


def test_summary_is_scoped_to_the_owner_and_skips_orphaned_results():
    mine = task()
    theirs = task(user_id=str(uuid4()))
    orphan = execution(task(), created_at="2026-11-11T10:00:00+00:00")
    result = summary([mine, theirs], [execution(mine), execution(theirs), orphan])
    assert result["outcomes_logged"] == 1
    assert result["total_xp"] == 22


def test_empty_history_starts_at_level_one():
    result = summary([], [])
    assert result["total_xp"] == 0
    assert result["level"] == 1
    assert result["progress"] == 0
    assert result["recent"] == []
    assert all(day["xp"] == 0 for day in result["daily_xp"])


def test_repository_reads_every_page(monkeypatch):
    monkeypatch.setattr(gamification_repository, "PAGE_SIZE", 2)
    plans = [task() for _ in range(5)]
    result = summary(plans, [execution(plan) for plan in plans])
    assert result["outcomes_logged"] == 5


# ── API ─────────────────────────────────────────────────────────────────────


def test_endpoint_returns_summary_and_validates_timezone(authenticated_client):
    plan = task()
    db = MemoryDatabase({"tasks": [plan], "executions": [execution(plan)]})
    app.dependency_overrides[get_primary_database] = lambda: db
    response = authenticated_client.get(
        "/gamification/summary", params={"timezone": "America/Denver"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total_xp"] == 22
    assert body["level"] == 1
    assert body["recent"][0]["task_id"] == plan["id"]
    bad = authenticated_client.get("/gamification/summary", params={"timezone": "Mars/Base"})
    assert bad.status_code == 422


def test_endpoint_requires_auth(client):
    assert client.get("/gamification/summary").status_code == 401
