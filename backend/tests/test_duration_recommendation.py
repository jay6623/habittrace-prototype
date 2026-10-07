from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.dependencies.database import get_primary_database
from app.main import app
from app.repositories.duration_repository import DurationRepository
from app.services.duration_service import DurationService

from .conftest import USER_ID
from .fake_supabase import MemoryDatabase

NOW = datetime(2026, 10, 6, tzinfo=timezone.utc)


def observation(minutes=45, *, title="Read", category="Study", planned=30):
    start = NOW - timedelta(days=1)
    return {
        "task_id": str(uuid4()),
        "ai_plan_input_id": str(uuid4()),
        "user_id": str(USER_ID),
        "actual_start_time": start.isoformat(),
        "actual_end_time": (start + timedelta(minutes=minutes)).isoformat(),
        "outcome_status": "completed",
        "task_status": "success",
        "plan": {
            "title": title,
            "category": category,
            "planned_duration_minutes": planned,
            "captured_at": (start - timedelta(hours=1)).isoformat(),
        },
    }


class History:
    def __init__(self, rows):
        self.rows = rows

    def list_observations(self, user_id):
        assert user_id == USER_ID
        return self.rows


def recommend(rows, **kwargs):
    return DurationService(History(rows)).get(USER_ID, " read ", "Study", 30, now=NOW, **kwargs)


def test_sparse_history_keeps_duration_unset():
    result = recommend([observation(), observation()])
    assert not result.available
    assert result.recommended_minutes is None


def test_exact_title_uses_median_and_resists_outlier():
    result = recommend([observation(m) for m in [34, 36, 700]])
    assert result.available
    assert result.basis == "same_title"
    assert result.sample_count == 3
    assert result.median_elapsed_minutes == 36
    assert result.recommended_minutes == 35


@pytest.mark.parametrize("minutes,expected", [(300, 45), (2, 15)])
def test_adjustment_is_bounded(minutes, expected):
    assert recommend([observation(minutes) for _ in range(3)]).recommended_minutes == expected


def test_category_needs_five_similarly_sized_original_plans():
    rows = [observation(title=str(i)) for i in range(5)]
    result = recommend(rows)
    assert result.available and result.basis == "similar_category"
    assert result.sample_count == 5
    rows[-1]["plan"]["planned_duration_minutes"] = 180
    assert not recommend(rows).available


@pytest.mark.parametrize(
    "patch",
    [
        {"outcome_status": "partial"},
        {"outcome_status": "not_started"},
        {"task_status": "failed"},
        {"plan": None},
        {"actual_end_time": (NOW + timedelta(days=1)).isoformat()},
        {"actual_end_time": (NOW - timedelta(days=100)).isoformat()},
        {"actual_start_time": "2026-10-05T00:00:00"},
        {"actual_end_time": "bad"},
        {"actual_end_time": "2026-10-04T00:00:00+00:00"},
    ],
)
def test_invalid_or_incomplete_results_never_supply_missing_third_sample(patch):
    assert not recommend([observation(), observation(), {**observation(), **patch}]).available


def test_retrospective_plan_wrong_category_duplicates_and_current_task_are_excluded():
    rows = [observation() for _ in range(6)]
    rows[2]["plan"]["captured_at"] = NOW.isoformat()
    rows[3]["plan"]["category"] = "Work"
    rows[4] = rows[0]
    assert not recommend(rows, exclude_task_id=rows[5]["task_id"]).available


def database(rows):
    return MemoryDatabase(
        {
            "executions": [{k: v for k, v in row.items() if k != "plan"} for row in rows],
            "task_ai_sync_jobs": [
                {
                    "id": row["ai_plan_input_id"],
                    "user_id": row["user_id"],
                    "created_at": row["plan"]["captured_at"],
                    "payload": row["plan"],
                }
                for row in rows
            ],
        }
    )


def test_repository_scopes_both_execution_and_snapshot_to_owner():
    rows = [observation() for _ in range(3)]
    rows[1]["user_id"] = str(uuid4())
    db = database(rows)
    db.rows["task_ai_sync_jobs"][2]["user_id"] = str(uuid4())
    result = DurationService(DurationRepository(db)).get(USER_ID, "Read", "Study", 30, now=NOW)
    assert not result.available
    assert result.sample_count == 1


def test_authenticated_endpoint_and_bounds(authenticated_client):
    db = database([observation() for _ in range(3)])
    app.dependency_overrides[get_primary_database] = lambda: db
    # Use current timestamps so this route test does not depend on calendar time.
    for table in db.rows.values():
        for row in table:
            if "actual_end_time" in row:
                start = datetime.now(timezone.utc) - timedelta(hours=2)
                row["actual_start_time"] = start.isoformat()
                row["actual_end_time"] = (start + timedelta(minutes=40)).isoformat()
            if "payload" in row:
                row["created_at"] = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    url = "/analytics/duration-recommendation"
    params = {"title": "Read", "category": "Study", "planned_minutes": 30}
    response = authenticated_client.get(url, params=params)
    assert response.status_code == 200
    assert response.json()["recommended_minutes"] == 40
    for value in [0, 481, "invalid"]:
        assert (
            authenticated_client.get(url, params={**params, "planned_minutes": value}).status_code
            == 422
        )
    assert (
        authenticated_client.get(url, params={**params, "exclude_task_id": "bad"}).status_code
        == 422
    )


def test_endpoint_requires_auth(client):
    response = client.get(
        "/analytics/duration-recommendation",
        params={
            "title": "Read",
            "category": "Study",
            "planned_minutes": 30,
        },
    )
    assert response.status_code == 401
