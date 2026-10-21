from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator

OutcomeStatus = Literal["not_started", "partial", "completed", "abandoned"]
FAILURE_REASONS = {
    "low_readiness", "schedule_overload", "underestimated_time", "interruption",
    "unexpected_event", "unclear_plan", "task_too_difficult", "other",
}


class ExecutionFacts(BaseModel):
    # None means not reported (unknown); 0 is a reported zero. Older clients send 0.
    interruption_count: int | None = Field(default=0, ge=0, le=10000)
    stopped_early: bool = False
    task_status: Literal["success", "failed"]
    failure_reason: str | None = Field(default=None, max_length=100)
    outcome_status: OutcomeStatus | None = None
    completion_ratio: Decimal | None = Field(default=None, ge=0, le=1, decimal_places=5)
    active_minutes: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_facts(self) -> "ExecutionFacts":
        if self.task_status == "success":
            if self.outcome_status not in (None, "completed"):
                raise ValueError("A successful execution must be completed")
            if self.completion_ratio not in (None, Decimal("1")):
                raise ValueError("Completed executions must have completion_ratio 1")
            self.outcome_status, self.completion_ratio = "completed", Decimal("1")
            self.failure_reason = None
        elif self.outcome_status == "completed":
            raise ValueError("Completed executions must have task_status success")
        if self.outcome_status == "partial":
            if self.completion_ratio is None or not 0 < self.completion_ratio < 1:
                raise ValueError("Specify the actual partial completion_ratio between 0 and 1")
        elif self.outcome_status in ("not_started", "abandoned"):
            if self.completion_ratio not in (None, Decimal("0")):
                raise ValueError("This outcome must have completion_ratio 0")
            self.completion_ratio = Decimal("0")
        elif self.outcome_status is None and self.completion_ratio is not None:
            raise ValueError("outcome_status is required with completion_ratio")
        if self.outcome_status == "not_started":
            if (
                self.interruption_count or self.stopped_early
                or self.active_minutes not in (None, 0)
            ):
                raise ValueError("Not-started outcomes cannot contain execution activity")
            self.active_minutes = 0
            self.interruption_count = 0  # nothing was executed, so zero is confirmed
        # A failure reason is optional; a missing reason is unknown, not "other".
        if self.failure_reason:
            self.failure_reason = self.failure_reason.strip() or None
        if self.outcome_status is not None and self.failure_reason not in (None, *FAILURE_REASONS):
            raise ValueError("Choose a supported failure_reason")
        return self


class ExecutionTimes(ExecutionFacts):
    """Actual times are optional; None means unknown and is never filled with a guess.

    An end without a start is a user-reported finish time. ``actual_end_unknown``
    asks the server not to stamp the request time as the finish of a running timer.
    """

    actual_start_time: AwareDatetime | None = None
    actual_end_time: AwareDatetime | None = None
    actual_end_unknown: bool = False

    @model_validator(mode="after")
    def validate_times(self) -> "ExecutionTimes":
        if self.outcome_status == "not_started":
            if self.actual_start_time is not None or self.actual_end_time is not None:
                raise ValueError("Not-started outcomes cannot contain actual times")
            return self
        if self.actual_end_unknown and self.actual_end_time is not None:
            raise ValueError("An unknown finish time cannot also be provided")
        latest_allowed = datetime.now(timezone.utc) + timedelta(minutes=5)
        for value in (self.actual_start_time, self.actual_end_time):
            if value is not None and value > latest_allowed:
                raise ValueError("Actual times cannot be in the future")
        if self.actual_start_time is not None and self.actual_end_time is not None:
            if self.actual_end_time < self.actual_start_time:
                raise ValueError("End time must follow start time")
            elapsed = int((self.actual_end_time - self.actual_start_time).total_seconds() // 60)
            if self.active_minutes is not None and self.active_minutes > elapsed:
                raise ValueError("Active minutes cannot exceed elapsed time")
        return self


class ExecutionCreate(ExecutionTimes):
    task_id: str
    idempotency_key: UUID | None = None


class ExecutionStart(BaseModel):
    task_id: str


class ExecutionComplete(ExecutionTimes):
    pass


class ExecutionResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    actual_start_time: str | None
    actual_end_time: str | None
    interruption_count: int | None
    stopped_early: bool
    task_status: Literal["success", "failed"] | None
    failure_reason: str | None
    outcome_status: OutcomeStatus | None = None
    completion_ratio: Decimal | None = None
    active_minutes: int | None = None
    ai_outcome_sync_status: str = "unlinked"
    created_at: str
