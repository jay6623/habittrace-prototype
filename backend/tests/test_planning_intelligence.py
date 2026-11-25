from copy import deepcopy
from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest

from app.core.errors import DomainValidationError
from app.main import app
from app.routes.planning_intelligence import personal_service, project_service
from app.schemas.group import GroupPersonalPlanRequest
from app.schemas.planning_intelligence import ProjectDependency
from app.services.planning_intelligence_service import PlanningIntelligenceService
from app.services.project_forecast_service import ProjectForecastService

from . import test_group_personal_planning as group_cases
from .conftest import USER_ID
from .test_group_personal_planning import BODY
from .test_groups_api import OTHER_ID, OWN_GROUP_ID, OWN_TASK_ID

GROUP = f"/groups/{OWN_GROUP_ID}"
NOW = datetime(2099, 9, 6, 8, tzinfo=timezone.utc)


@pytest.fixture
def intelligence(monkeypatch):
    db, planner, _, _ = group_cases.setup.__wrapped__(monkeypatch)
    source = planner.confirm(
        USER_ID,
        UUID(OWN_GROUP_ID),
        UUID(OWN_TASK_ID),
        GroupPersonalPlanRequest(**BODY),
    )
    planner.model.model_version = "fixture-v1"
    private = PlanningIntelligenceService(planner)
    project = ProjectForecastService(planner.groups)
    app.dependency_overrides[personal_service] = lambda: private
    app.dependency_overrides[project_service] = lambda: project
    return db, source, private, project


def test_comparison_preserves_full_scope_and_records_no_plan_write(
    authenticated_client, intelligence
):
    db, source, _, _ = intelligence
    before = deepcopy(db.rows["tasks"])
    response = authenticated_client.post("/planning/compare", json={"task_id": source["id"]})
    assert response.status_code == 200, response.text
    assert response.headers["cache-control"] == "no-store"
    result = response.json()
    split = next(o for o in result["options"] if o["id"] == "split")
    assert split["total_minutes"] == 60
    assert sum(b["duration_minutes"] for b in split["blocks"]) == 60
    assert len(split["blocks"]) == 2
    assert "success_probability" not in split
    assert db.rows["tasks"] == before
    assert db.rows["planning_comparisons"][0]["source_task_id"] == source["id"]
    assert result["evidence"]["history_samples"] == 0
    import json

    json.dumps(db.rows["planning_comparisons"][0])
    assert not result["evidence"]["duration"]["available"]


def test_partial_result_creates_remaining_work_estimate_not_fake_completion(
    authenticated_client, intelligence
):
    db, source, _, _ = intelligence
    db.rows["tasks"][0]["task_status"] = "failed"
    db.rows["executions"] = [
        {
            "id": str(uuid4()),
            "task_id": source["id"],
            "user_id": str(USER_ID),
            "task_status": "failed",
            "outcome_status": "partial",
            "completion_ratio": 0.4,
            "created_at": "2099-09-05T12:00:00Z",
        }
    ]
    result = authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).json()
    assert result["evidence"]["remaining_minutes"] == 36
    assert result["evidence"]["continuation"]
    assert db.rows["tasks"][0]["task_status"] == "failed"
    overridden = authenticated_client.post(
        "/planning/compare", json={"task_id": source["id"], "remaining_minutes": 50}
    ).json()
    assert overridden["evidence"]["remaining_minutes"] == 50
    assert overridden["evidence"]["remaining_basis"] == "your_estimate"


def test_private_comparison_does_not_accept_other_users_plan(authenticated_client, intelligence):
    db, source, _, _ = intelligence
    db.rows["tasks"][0]["user_id"] = OTHER_ID
    assert (
        authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).status_code
        == 404
    )
    assert not db.rows.get("planning_comparisons")


def test_closed_and_running_plans_are_not_rewritten(authenticated_client, intelligence):
    db, source, _, _ = intelligence
    db.rows["tasks"][0]["task_status"] = "success"
    assert (
        authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).status_code
        == 409
    )
    db.rows["tasks"][0]["task_status"] = "pending"
    db.rows["executions"] = [
        {
            "id": str(uuid4()),
            "task_id": source["id"],
            "user_id": str(USER_ID),
            "task_status": None,
            "created_at": "2099-09-05T12:00:00Z",
        }
    ]
    assert (
        authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).status_code
        == 409
    )


def test_unavailable_options_and_unconfirmed_writes_are_rejected(
    authenticated_client, intelligence
):
    db, source, _, _ = intelligence
    result = authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).json()
    url = f"/planning/comparisons/{result['id']}/apply"
    assert (
        authenticated_client.post(url, json={"option_id": "split", "confirmed": False}).status_code
        == 422
    )
    db.rows["planning_comparisons"][0]["options"][0]["available"] = False
    assert (
        authenticated_client.post(url, json={"option_id": "current", "confirmed": True}).status_code
        == 422
    )


def test_viewed_event_is_owned_and_idempotent(authenticated_client, intelligence):
    db, source, _, _ = intelligence
    result = authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).json()
    assert authenticated_client.get("/planning/evaluation").json()["shown"] == 0
    for _ in range(2):
        assert (
            authenticated_client.post(f"/planning/comparisons/{result['id']}/viewed").status_code
            == 200
        )
    assert authenticated_client.get("/planning/evaluation").json()["shown"] == 1
    db.rows["planning_comparisons"][0]["user_id"] = OTHER_ID
    assert (
        authenticated_client.post(f"/planning/comparisons/{result['id']}/viewed").status_code == 404
    )


def test_evaluation_only_matches_prospective_exact_snapshots_once(
    authenticated_client, intelligence
):
    db, source, private, _ = intelligence
    snap = "snapshot-1"
    comparison = {
        "id": str(uuid4()),
        "user_id": str(USER_ID),
        "shown_at": "2099-09-01T10:00:00+00:00",
        "displayed_at": "2099-09-01T10:00:00+00:00",
        "selected_at": "2099-09-01T10:01:00+00:00",
        "applied_snapshots": [{"task_id": source["id"], "plan_input_id": snap, "probability": 0.8}],
    }
    db.rows["planning_comparisons"] = [comparison, {**comparison, "id": str(uuid4())}]
    db.rows["executions"] = [
        {
            "id": str(uuid4()),
            "task_id": source["id"],
            "user_id": str(USER_ID),
            "ai_plan_input_id": snap,
            "task_status": "success",
            "created_at": "2099-09-02T12:00:00+00:00",
            "actual_start_time": "2099-09-02T10:00:00+00:00",
        }
    ]
    evaluation = private.evaluation(USER_ID)
    assert evaluation["evaluated"] == {"count": 1, "brier_score": 0.04}
    db.rows["executions"][0]["actual_start_time"] = None
    assert private.evaluation(USER_ID)["evaluated"]["count"] == 0
    db.rows["executions"][0]["actual_start_time"] = "2099-08-31T10:00:00Z"
    assert private.evaluation(USER_ID)["evaluated"]["count"] == 0
    db.rows["executions"][0]["actual_start_time"] = "2099-09-02T10:00:00Z"
    db.rows["executions"][0]["ai_plan_input_id"] = "edited-snapshot"
    assert private.evaluation(USER_ID)["evaluated"]["count"] == 0


def seed_project(db):
    original = db.rows["group_tasks"][0]
    original.update(estimated_duration_minutes=120, due_date="2099-09-09")
    second = {**original, "id": str(uuid4()), "title": "Write draft"}
    db.rows["group_tasks"].append(second)
    db.rows["group_task_assignees"] = [
        {
            "group_id": OWN_GROUP_ID,
            "task_id": original["id"],
            "user_id": str(USER_ID),
            "shared_remaining_minutes": 120,
        },
        {
            "group_id": OWN_GROUP_ID,
            "task_id": second["id"],
            "user_id": OTHER_ID,
            "shared_remaining_minutes": 60,
        },
    ]
    for member in db.rows["group_members"]:
        if member["group_id"] == OWN_GROUP_ID:
            member.update(shared_minutes_per_day=60, capacity_until="2099-09-15")
    db.rows["group_task_dependencies"] = [
        {"group_id": OWN_GROUP_ID, "task_id": second["id"], "predecessor_id": original["id"]}
    ]
    return original, second


def test_dependency_forecast_respects_capacity_and_never_reads_private_plans(intelligence):
    db, _, _, project = intelligence
    first, second = seed_project(db)
    db.rows["tasks"] = [{"user_id": OTHER_ID, "title": "PRIVATE SECRET"}]
    forecast = project.forecast(USER_ID, UUID(OWN_GROUP_ID), "UTC", now=NOW)
    tasks = {t["task_id"]: t for t in forecast["tasks"]}
    assert tasks[first["id"]]["downstream_count"] == 1
    assert tasks[second["id"]]["blocked_by"] == [first["id"]]
    assert datetime.fromisoformat(tasks[second["id"]]["forecast_finish"]) > datetime.fromisoformat(
        tasks[first["id"]]["forecast_finish"]
    )
    assert "PRIVATE SECRET" not in str(forecast)
    assert "success_probability" not in str(forecast)


def test_missing_capacity_and_remaining_work_stay_unknown(intelligence):
    db, _, _, project = intelligence
    seed_project(db)
    for member in db.rows["group_members"]:
        member["shared_minutes_per_day"] = None
    result = project.forecast(USER_ID, UUID(OWN_GROUP_ID), "UTC", now=NOW)
    assert all(t["forecast_finish"] is None for t in result["tasks"])
    assert all(t["status"] == "unknown" for t in result["tasks"])


def test_cycles_and_cross_group_dependencies_are_rejected(intelligence):
    db, _, _, project = intelligence
    first, second = seed_project(db)
    with pytest.raises(DomainValidationError, match="cycle"):
        project.dependency(
            USER_ID,
            UUID(OWN_GROUP_ID),
            ProjectDependency(task_id=first["id"], predecessor_id=second["id"]),
        )
    foreign = db.rows["group_tasks"][1]["id"]
    response = __import__(
        "app.core.errors", fromlist=["ResourceNotFoundError"]
    ).ResourceNotFoundError
    with pytest.raises(response):
        project.dependency(
            USER_ID,
            UUID(OWN_GROUP_ID),
            ProjectDependency(task_id=first["id"], predecessor_id=foreign),
        )


def test_milestone_requires_linked_completion_and_explicit_review(
    authenticated_client, intelligence
):
    db, _, _, project = intelligence
    first, second = seed_project(db)
    result = authenticated_client.post(
        GROUP + "/milestones",
        json={
            "title": "Draft ready",
            "due_date": "2099-09-10",
            "task_ids": [first["id"], second["id"]],
            "completion_criteria": "Every section is ready for review.",
        },
    )
    assert result.status_code == 200, result.text
    milestone = result.json()["id"]
    assert authenticated_client.post(GROUP + f"/milestones/{milestone}/confirm").status_code == 422
    for row in db.rows["group_task_assignees"]:
        row["outcome"] = "success"
    assert (
        project.forecast(USER_ID, UUID(OWN_GROUP_ID), now=NOW)["milestones"][0]["status"]
        == "review"
    )
    assert authenticated_client.post(GROUP + f"/milestones/{milestone}/confirm").status_code == 200
    assert (
        project.forecast(USER_ID, UUID(OWN_GROUP_ID), now=NOW)["milestones"][0]["status"]
        == "complete"
    )


def test_capacity_remaining_and_help_are_self_scoped(authenticated_client, intelligence):
    db, _, _, _ = intelligence
    seed_project(db)
    before = deepcopy(db.rows["group_members"][1])
    assert (
        authenticated_client.patch(
            GROUP + "/my-capacity", json={"minutes_per_day": 90, "available_until": "2099-09-15"}
        ).status_code
        == 200
    )
    assert db.rows["group_members"][1] == before
    assert (
        authenticated_client.patch(GROUP + "/my-capacity", json={"minutes_per_day": 90}).status_code
        == 422
    )
    assert (
        authenticated_client.patch(
            GROUP + f"/tasks/{OWN_TASK_ID}/my-remaining-work", json={"remaining_minutes": 30}
        ).status_code
        == 200
    )
    request = authenticated_client.post(
        GROUP + "/help-requests",
        json={
            "task_id": OWN_TASK_ID,
            "helper_id": OTHER_ID,
            "message": "Please review the introduction.",
        },
    )
    assert request.status_code == 200, request.text
    assert (
        authenticated_client.patch(
            GROUP + f"/help-requests/{request.json()['id']}", json={"status": "accepted"}
        ).status_code
        == 404
    )
    assert db.rows["group_help_requests"][0].get("status", "pending") == "pending"
    assert (
        authenticated_client.patch(
            GROUP + "/my-capacity", json={"minutes_per_day": None}
        ).status_code
        == 200
    )
    assert db.rows["group_members"][0]["shared_minutes_per_day"] is None


@pytest.mark.parametrize(
    "method,path,body",
    [
        ("post", "/planning/compare", {"task_id": str(uuid4())}),
        ("get", "/planning/evaluation", None),
        ("get", GROUP + "/forecast", None),
        (
            "post",
            GROUP + "/dependencies",
            {"task_id": str(uuid4()), "predecessor_id": str(uuid4())},
        ),
        ("patch", GROUP + "/my-capacity", {"minutes_per_day": None}),
    ],
)
def test_new_endpoints_require_auth(client, intelligence, method, path, body):
    assert client.request(method, path, json=body).status_code == 401


def test_shared_timezone_is_consistent_across_viewers_and_admin_only(
    authenticated_client, intelligence
):
    db, _, _, project = intelligence
    seed_project(db)
    result = authenticated_client.patch(
        GROUP + "/planning-timezone", json={"timezone_name": "America/Denver"}
    )
    assert result.status_code == 200, result.text
    assert (
        project.forecast(USER_ID, UUID(OWN_GROUP_ID), "Asia/Seoul", now=NOW)["timezone_name"]
        == "America/Denver"
    )
    assert (
        authenticated_client.patch(
            GROUP + "/planning-timezone", json={"timezone_name": "Invalid/Zone"}
        ).status_code
        == 422
    )
    db.rows["group_members"][0]["role"] = "member"
    assert (
        authenticated_client.patch(
            GROUP + "/planning-timezone", json={"timezone_name": "UTC"}
        ).status_code
        == 403
    )


def test_milestone_can_be_corrected_and_removed_without_deleting_work(
    authenticated_client, intelligence
):
    db, _, _, _ = intelligence
    first, second = seed_project(db)
    body = {
        "title": "Draft ready",
        "due_date": "2099-09-10",
        "task_ids": [first["id"]],
        "completion_criteria": "Complete all sections.",
        "timezone_name": "America/Denver",
    }
    response = authenticated_client.post(GROUP + "/milestones", json=body)
    assert response.status_code == 200, response.text
    key = response.json()["id"]
    edited = authenticated_client.patch(
        GROUP + f"/milestones/{key}", json={**body, "task_ids": [second["id"]]}
    )
    assert edited.status_code == 200
    assert edited.json()["confirmed_at"] is None
    before = deepcopy(db.rows["group_tasks"])
    assert authenticated_client.delete(GROUP + f"/milestones/{key}").status_code == 200
    assert db.rows["group_tasks"] == before
    assert db.rows["group_project_milestones"] == []


def test_all_split_blocks_include_other_blocks_in_daily_load(authenticated_client, intelligence):
    _, source, _, _ = intelligence
    result = authenticated_client.post("/planning/compare", json={"task_id": source["id"]}).json()
    split = next(o for o in result["options"] if o["id"] == "split")
    same_day = split["blocks"][0]["local_date"] == split["blocks"][1]["local_date"]
    if same_day:
        assert all(b["daily_minutes"] >= split["total_minutes"] for b in split["blocks"])
    assert all("feature_snapshot" in b and "prediction_snapshot" in b for b in split["blocks"])
