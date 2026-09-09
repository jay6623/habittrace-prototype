from __future__ import annotations

import pytest

from app.core.errors import (
    DomainValidationError,
    ResourceConflictError,
    ResourceNotFoundError,
)
from app.schemas.ai_failure_reason import FailureReasonCreate
from app.schemas.ai_outcome import OutcomeCreate
from app.schemas.ai_plan import PlanInputCreate
from app.services.ai_failure_reason_service import AIFailureReasonService
from app.services.ai_outcome_service import AIOutcomeService
from app.services.ai_plan_service import AIPlanService

from .conftest import OUTCOME_ID, PLAN_ID, USER_ID
from .factories import outcome_row, plan_row


class PlanRepositoryFake:
    def __init__(self) -> None:
        self.created = None
        self.rows = [
            {
                "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                "parent_plan_input_id": None,
                "planned_start": "2026-07-14T08:00:00+00:00",
                "planned_duration_minutes": 60,
            },
            {
                "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                "parent_plan_input_id": None,
                "planned_start": "2026-07-14T10:00:00+00:00",
                "planned_duration_minutes": 30,
            },
        ]

    def get_owned(self, plan_input_id, user_id):
        return plan_row(id=str(plan_input_id), user_id=str(user_id))

    def has_child(self, plan_input_id):
        return False

    def list_schedule_rows(self, user_id):
        return self.rows

    def create(self, payload):
        self.created = payload
        return plan_row(**payload)


def test_plan_service_calculates_schedule_context() -> None:
    repository = PlanRepositoryFake()
    service = AIPlanService(repository)
    body = PlanInputCreate(
        title="New plan",
        category="work",
        planned_start="2026-07-14T11:00:00+00:00",
        planned_duration_minutes=45,
        timezone_name="UTC",
    )

    service.create(USER_ID, body)

    assert repository.created["tasks_before_count"] == 2
    assert repository.created["planned_minutes_before"] == 90
    assert repository.created["daily_planned_minutes"] == 135
    assert repository.created["minutes_since_previous"] == 30


def test_revision_requires_reschedule_or_recommendation_source() -> None:
    service = AIPlanService(PlanRepositoryFake())
    body = PlanInputCreate(
        parent_plan_input_id=PLAN_ID,
        input_source="user",
        title="Revised plan",
        category="work",
        planned_start="2026-07-14T11:00:00+00:00",
        planned_duration_minutes=45,
        timezone_name="UTC",
    )

    with pytest.raises(DomainValidationError):
        service.create(USER_ID, body)


def test_revision_creates_child_with_parent_and_reschedule_source() -> None:
    repository = PlanRepositoryFake()
    service = AIPlanService(repository)
    body = PlanInputCreate(
        parent_plan_input_id=PLAN_ID,
        input_source="reschedule",
        title="Revised plan",
        category="work",
        planned_start="2026-07-14T11:00:00+00:00",
        planned_duration_minutes=45,
        timezone_name="UTC",
    )

    service.create(USER_ID, body)

    assert repository.created["parent_plan_input_id"] == str(PLAN_ID)
    assert repository.created["input_source"] == "reschedule"


def test_revision_rejects_parent_that_already_has_child() -> None:
    repository = PlanRepositoryFake()
    repository.has_child = lambda _plan_input_id: True
    service = AIPlanService(repository)
    body = PlanInputCreate(
        parent_plan_input_id=PLAN_ID,
        input_source="reschedule",
        title="Second revision",
        category="work",
        planned_start="2026-07-14T11:00:00+00:00",
        planned_duration_minutes=45,
        timezone_name="UTC",
    )

    with pytest.raises(ResourceConflictError):
        service.create(USER_ID, body)


def test_revision_rejects_parent_owned_by_another_user() -> None:
    repository = PlanRepositoryFake()
    repository.get_owned = lambda _plan_input_id, _user_id: None
    service = AIPlanService(repository)
    body = PlanInputCreate(
        parent_plan_input_id=PLAN_ID,
        input_source="reschedule",
        title="Unauthorized revision",
        category="work",
        planned_start="2026-07-14T11:00:00+00:00",
        planned_duration_minutes=45,
        timezone_name="UTC",
    )

    with pytest.raises(ResourceNotFoundError):
        service.create(USER_ID, body)


class OutcomeRepositoryFake:
    def __init__(self, existing=None) -> None:
        self.existing = existing
        self.created = None

    def get_by_plan(self, plan_input_id):
        return self.existing

    def create(self, payload):
        self.created = payload
        return outcome_row(**payload)


def test_outcome_service_rejects_second_outcome() -> None:
    outcomes = OutcomeRepositoryFake(existing=outcome_row())
    service = AIOutcomeService(PlanRepositoryFake(), outcomes)

    with pytest.raises(ResourceConflictError):
        service.create(
            USER_ID,
            PLAN_ID,
            OutcomeCreate(outcome_status="not_started"),
        )


def test_outcome_service_hides_non_owned_plan() -> None:
    plans = PlanRepositoryFake()
    plans.get_owned = lambda plan_input_id, user_id: None
    service = AIOutcomeService(plans, OutcomeRepositoryFake())

    with pytest.raises(ResourceNotFoundError):
        service.create(
            USER_ID,
            PLAN_ID,
            OutcomeCreate(outcome_status="not_started"),
        )


class FailureReasonRepositoryFake:
    def __init__(self, active_codes: set[str]) -> None:
        self.active_codes = active_codes
        self.created = None

    def list_active_definitions(self):
        return []

    def list_for_outcome(self, outcome_id):
        return []

    def find_active_codes(self, reason_codes):
        return self.active_codes.intersection(reason_codes)

    def create_many(self, payload):
        self.created = payload
        return payload


class OutcomeLookupFake:
    def __init__(self, row):
        self.row = row

    def get_by_id(self, outcome_id):
        return self.row


def test_failure_reason_service_stores_only_server_confirmed_rows() -> None:
    reasons = FailureReasonRepositoryFake({"low_readiness", "interruption"})
    service = AIFailureReasonService(
        PlanRepositoryFake(), OutcomeLookupFake(outcome_row()), reasons
    )

    result = service.create_for_outcome(
        USER_ID,
        OUTCOME_ID,
        FailureReasonCreate(
            primary_reason_code="low_readiness",
            secondary_reason_codes=["interruption"],
        ),
    )

    assert result["user_confirmed"] is True
    assert all(row["user_confirmed"] is True for row in reasons.created)
    assert sum(row["is_primary"] for row in reasons.created) == 1


def test_failure_reason_service_rejects_unknown_code() -> None:
    reasons = FailureReasonRepositoryFake({"low_readiness"})
    service = AIFailureReasonService(
        PlanRepositoryFake(), OutcomeLookupFake(outcome_row()), reasons
    )

    with pytest.raises(DomainValidationError):
        service.create_for_outcome(
            USER_ID,
            OUTCOME_ID,
            FailureReasonCreate(primary_reason_code="not_a_real_reason"),
        )


def test_failure_reason_service_rejects_successful_outcome() -> None:
    reasons = FailureReasonRepositoryFake({"other"})
    successful = outcome_row(outcome_status="completed", completion_ratio=0.8)
    service = AIFailureReasonService(PlanRepositoryFake(), OutcomeLookupFake(successful), reasons)

    with pytest.raises(DomainValidationError):
        service.create_for_outcome(
            USER_ID,
            OUTCOME_ID,
            FailureReasonCreate(primary_reason_code="other"),
        )


def test_failure_reason_service_hides_non_owned_outcome() -> None:
    plans = PlanRepositoryFake()
    plans.get_owned = lambda plan_input_id, user_id: None
    service = AIFailureReasonService(
        plans,
        OutcomeLookupFake(outcome_row()),
        FailureReasonRepositoryFake({"other"}),
    )

    with pytest.raises(ResourceNotFoundError):
        service.create_for_outcome(
            USER_ID,
            OUTCOME_ID,
            FailureReasonCreate(primary_reason_code="other"),
        )
