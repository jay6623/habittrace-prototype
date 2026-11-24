from datetime import date, timedelta
from uuid import uuid4

import pytest

from app.services.gamification_rewards import (
    compute_streak,
    evaluate_rewards,
    start_time_of,
)

TODAY = date(2026, 11, 23)


def day(offset: int) -> str:
    """ISO date `offset` days before TODAY."""
    return (TODAY - timedelta(days=offset)).isoformat()


def plan(**updates):
    row = {
        "id": str(uuid4()),
        "title": "Plan",
        "task_category": "Study",
        "planned_date": day(0),
        "planned_start_time": "2:00 PM",
        "planned_duration_min": 60,
        "importance": 3,
    }
    row.update(updates)
    return row


def scored(task, outcome="completed", ratio=1.0, recorded="2026-11-01T00:00:00+00:00"):
    return {
        "task_id": task["id"],
        "planned_date": task["planned_date"],
        "outcome": outcome,
        "completion_ratio": ratio,
        "_recorded_at": recorded,
    }


def rewards(pairs):
    tasks = {t["id"]: t for t, _ in pairs}
    events = [e for _, e in pairs if e is not None]
    return evaluate_rewards(events, tasks, TODAY)


def badge(result, badge_id):
    return next(a for a in result["achievements"] if a["id"] == badge_id)


def milestone(result, milestone_id):
    return next(m for m in result["milestones"] if m["id"] == milestone_id)


def completed(**updates):
    task = plan(**updates)
    return task, scored(task)


# ── Start time parsing ──────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "value,expected",
    [
        ("2:00 PM", (14, 0)),
        ("2:30pm", (14, 30)),
        ("7 AM", (7, 0)),
        ("12:15 AM", (0, 15)),
        ("12:00 PM", (12, 0)),
        ("14:30", (14, 30)),
        ("08:05:00", (8, 5)),
        ("13:00 PM", None),
        ("25:00", None),
        ("soon", None),
        (None, None),
    ],
)
def test_start_time_of_reads_stored_formats(value, expected):
    assert start_time_of(value) == expected


# ── Streaks ─────────────────────────────────────────────────────────────────


def test_streak_runs_through_today_when_today_is_done():
    streak = compute_streak([day(0), day(1), day(2), day(5)], TODAY, [3, 7])
    assert (streak.current, streak.longest, streak.active_today) == (3, 3, True)
    assert streak.reached == {3: day(0)}


def test_streak_stays_alive_until_today_ends():
    streak = compute_streak([day(1), day(2)], TODAY, [3])
    assert (streak.current, streak.active_today) == (2, False)


def test_streak_breaks_after_a_missed_day_but_longest_is_kept():
    days = [day(10), day(9), day(8), day(7), day(2)]
    streak = compute_streak(days, TODAY, [3])
    assert (streak.current, streak.longest) == (0, 4)
    assert streak.reached == {3: day(8)}


def test_streak_ignores_future_and_duplicate_days():
    streak = compute_streak([day(0), day(0), day(-1), "bad"], TODAY, [3])
    assert (streak.current, streak.longest) == (1, 1)


# ── Achievements ────────────────────────────────────────────────────────────


def test_no_history_unlocks_nothing():
    result = rewards([])
    assert not any(a["unlocked"] for a in result["achievements"])
    assert result["bonus_by_day"] == {}
    assert result["recent_unlocks"] == []


def test_first_step_is_dated_by_the_first_completed_plan():
    first = completed(planned_date=day(4))
    later = completed(planned_date=day(1))
    missed_task = plan(planned_date=day(6))
    result = rewards([later, first, (missed_task, scored(missed_task, "not_started", 0))])
    first_step = badge(result, "first_step")
    assert first_step["unlocked"] and first_step["unlocked_on"] == day(4)
    assert result["bonus_by_day"][day(4)] == 25


def test_early_bird_and_night_owl_need_five_completed_plans_at_those_times():
    early = [completed(planned_date=day(i), planned_start_time="7:30 AM") for i in range(5)]
    late = [completed(planned_date=day(i), planned_start_time="21:00") for i in range(4)]
    not_done = plan(planned_start_time="6:00 AM")
    result = rewards([*early, *late, (not_done, scored(not_done, "abandoned", 0))])
    assert badge(result, "early_bird")["unlocked"]
    assert badge(result, "early_bird")["unlocked_on"] == day(0)
    assert badge(result, "night_owl")["progress"] == 4
    assert not badge(result, "night_owl")["unlocked"]


def test_nine_am_is_not_early_and_eight_pm_counts_as_night():
    result = rewards(
        [completed(planned_start_time="9:00 AM") for _ in range(5)]
        + [completed(planned_start_time="8:00 PM") for _ in range(5)]
    )
    assert badge(result, "early_bird")["progress"] == 0
    assert badge(result, "night_owl")["unlocked"]


def test_deep_work_explorer_and_team_player():
    categories = ["Study", "Work", "Health", "Personal", "Chores"]
    result = rewards(
        [completed(planned_duration_min=120)]
        + [completed(task_category=c, planned_date=day(i)) for i, c in enumerate(categories)]
        + [completed(source_group_task_id=str(uuid4())) for _ in range(5)]
    )
    assert badge(result, "deep_work")["unlocked"]
    assert badge(result, "explorer")["unlocked"]
    # The fifth distinct category ("Chores", 4 days ago) is the earliest day all
    # five exist when plans are taken in date order.
    assert badge(result, "explorer")["unlocked_on"] == day(0)
    assert badge(result, "team_player")["unlocked"]


def test_explorer_ignores_case_and_blank_categories():
    result = rewards(
        [completed(task_category=c) for c in ["Study", "study", " STUDY ", "", "Work"]]
    )
    assert badge(result, "explorer")["progress"] == 2


def test_honest_tracker_counts_outcomes_that_did_not_go_to_plan():
    tasks = [plan(planned_date=day(i)) for i in range(10)]
    result = rewards(
        [(t, scored(t, "partial" if i % 2 else "not_started", 0.5 if i % 2 else 0))
         for i, t in enumerate(tasks)]
    )
    assert badge(result, "honest_tracker")["unlocked"]
    assert badge(result, "honest_tracker")["unlocked_on"] == day(0)


def test_perfect_day_needs_three_plans_all_completed():
    full_day = [completed(planned_date=day(3)) for _ in range(3)]
    small_day = [completed(planned_date=day(2)) for _ in range(2)]
    pending = plan(planned_date=day(1))
    mixed_day = [completed(planned_date=day(1)) for _ in range(3)] + [(pending, None)]
    result = rewards(full_day + small_day + mixed_day)
    perfect = badge(result, "perfect_day")
    assert perfect["unlocked"] and perfect["unlocked_on"] == day(3)

    without_full_day = rewards(small_day + mixed_day)
    assert not badge(without_full_day, "perfect_day")["unlocked"]


def test_streak_badges_use_the_longest_run():
    result = rewards([completed(planned_date=day(i)) for i in range(7, 0, -1)])
    assert badge(result, "streak_3")["unlocked_on"] == day(5)
    assert badge(result, "streak_7")["unlocked_on"] == day(1)
    assert badge(result, "streak_30")["progress"] == 7
    assert result["streak"] == {"current": 7, "longest": 7, "active_today": False}


def test_correcting_an_outcome_removes_the_badge_it_earned():
    task = plan(planned_duration_min=180)
    assert badge(rewards([(task, scored(task))]), "deep_work")["unlocked"]
    corrected = rewards([(task, scored(task, "abandoned", 0))])
    assert not badge(corrected, "deep_work")["unlocked"]
    assert corrected["bonus_by_day"].get(task["planned_date"], 0) == 0


# ── Milestones ──────────────────────────────────────────────────────────────


def test_plan_milestone_is_dated_by_the_tenth_completion():
    result = rewards([completed(planned_date=day(i)) for i in range(12)])
    tracker = milestone(result, "plans_completed")
    assert tracker["value"] == 12
    assert tracker["tiers"][0] == {
        "target": 10, "bonus_xp": 25, "unlocked": True, "unlocked_on": day(2),
    }
    assert not tracker["tiers"][1]["unlocked"]


def test_focus_hours_include_the_done_share_of_partial_plans():
    full = [completed(planned_duration_min=60) for _ in range(9)]
    half_task = plan(planned_duration_min=120)
    result = rewards([*full, (half_task, scored(half_task, "partial", 0.5))])
    tracker = milestone(result, "focus_hours")
    assert tracker["value"] == 10.0
    assert tracker["tiers"][0]["unlocked"]


def test_outcome_milestone_counts_every_recorded_outcome():
    tasks = [plan() for _ in range(25)]
    result = rewards([(t, scored(t, "not_started", 0)) for t in tasks])
    assert milestone(result, "outcomes_logged")["tiers"][0]["unlocked"]
    assert milestone(result, "plans_completed")["value"] == 0


def test_bonus_xp_adds_up_every_unlock_and_recent_unlocks_are_newest_first():
    result = rewards([completed(planned_date=day(i)) for i in range(10, 0, -1)])
    expected = {
        "first_step": 25, "streak_3": 25, "streak_7": 50,
    }
    for badge_id in expected:
        assert badge(result, badge_id)["unlocked"]
    # Plus two milestones: 10 plans completed, and 10 hours (ten 60-minute plans).
    total_bonus = sum(expected.values()) + 25 + 25
    assert sum(result["bonus_by_day"].values()) == total_bonus
    dates = [u["unlocked_on"] for u in result["recent_unlocks"]]
    assert dates == sorted(dates, reverse=True)
    assert len(result["recent_unlocks"]) == 3
