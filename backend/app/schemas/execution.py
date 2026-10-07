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
    interruption_count: int = Field(default=0, ge=0, le=10000)
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
        if self.failure_reason:
            self.failure_reason = self.failure_reason.strip() or None
        if (
            self.task_status == "failed" and self.outcome_status != "not_started"
            and not self.failure_reason
        ):
            raise ValueError("failure_reason is required for a failed execution")
        if self.outcome_status is not None and self.failure_reason not in (None, *FAILURE_REASONS):
            raise ValueError("Choose a supported failure_reason")
        return self


class ExecutionTimes(ExecutionFacts):
    actual_start_time: AwareDatetime | None = None
    actual_end_time: AwareDatetime | None = None

    @model_validator(mode="after")
    def validate_times(self) -> "ExecutionTimes":
        if self.outcome_status == "not_started":
            if self.actual_start_time is not None or self.actual_end_time is not None:
                raise ValueError("Not-started outcomes cannot contain actual times")
            return self
        if (self.actual_start_time is None) != (self.actual_end_time is None):
            raise ValueError("Provide both actual start and end times, or neither")
        if self.actual_start_time is not None and self.actual_end_time is not None:
            if self.actual_end_time < self.actual_start_time:
                raise ValueError("End time must follow start time")
            if self.actual_end_time > datetime.now(timezone.utc) + timedelta(minutes=5):
                raise ValueError("Actual times cannot be in the future")
            elapsed = int((self.actual_end_time - self.actual_start_time).total_seconds() // 60)
            if self.active_minutes is not None and self.active_minutes > elapsed:
                raise ValueError("Active minutes cannot exceed elapsed time")
        return self


class ExecutionCreate(ExecutionTimes):
    task_id: str
    idempotency_key: UUID | None = None

    @model_validator(mode="after")
    def require_actual_times(self) -> "ExecutionCreate":
        if self.outcome_status != "not_started" and self.actual_start_time is None:
            raise ValueError("Actual start and end times are required")
        return self


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
    interruption_count: int
    stopped_early: bool
    task_status: Literal["success", "failed"] | None
    failure_reason: str | None
    outcome_status: OutcomeStatus | None = None
    completion_ratio: Decimal | None = None
    active_minutes: int | None = None
    ai_outcome_sync_status: str = "unlinked"
    created_at: str
