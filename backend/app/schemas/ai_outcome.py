"""Request and response contracts for post-execution outcomes."""
from __future__ import annotations

from decimal import Decimal
from enum import Enum
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator


class OutcomeStatus(str, Enum):
    NOT_STARTED = "not_started"
    PARTIAL = "partial"
    COMPLETED = "completed"
    ABANDONED = "abandoned"


class OutcomeCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    outcome_status: OutcomeStatus
    actual_start: AwareDatetime | None = None
    actual_end: AwareDatetime | None = None
    active_minutes: int | None = Field(default=None, ge=0)
    completion_ratio: Decimal = Field(default=Decimal("0"), ge=0, le=1, decimal_places=5)
    interruption_count: int = Field(default=0, ge=0)
    stopped_early: bool = False
    user_note: str | None = Field(default=None, max_length=5000)

    @field_validator("user_note")
    @classmethod
    def normalize_note(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @model_validator(mode="after")
    def validate_outcome(self) -> OutcomeCreate:
        if self.actual_end is not None and self.actual_start is None:
            raise ValueError("actual_start is required when actual_end is provided")
        if (
            self.actual_start is not None
            and self.actual_end is not None
            and self.actual_end < self.actual_start
        ):
            raise ValueError("actual_end must be at or after actual_start")
        if self.outcome_status is OutcomeStatus.NOT_STARTED:
            if self.actual_start is not None or self.actual_end is not None:
                raise ValueError("not_started outcomes cannot contain actual times")
            if self.active_minutes not in (None, 0):
                raise ValueError("not_started outcomes cannot contain active minutes")
            if self.completion_ratio != 0:
                raise ValueError("not_started outcomes must have completion_ratio 0")
            if self.interruption_count != 0 or self.stopped_early:
                raise ValueError("not_started outcomes cannot contain execution events")
        return self


class OutcomeResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    plan_input_id: UUID
    outcome_status: OutcomeStatus
    actual_start: AwareDatetime | None
    actual_end: AwareDatetime | None
    active_minutes: int | None
    completion_ratio: Decimal
    interruption_count: int
    stopped_early: bool
    user_note: str | None
    recorded_at: AwareDatetime


def outcome_to_insert(body: OutcomeCreate, *, plan_input_id: UUID) -> dict:
    return {
        "plan_input_id": str(plan_input_id),
        "outcome_status": body.outcome_status.value,
        "actual_start": body.actual_start.isoformat() if body.actual_start else None,
        "actual_end": body.actual_end.isoformat() if body.actual_end else None,
        "active_minutes": body.active_minutes,
        "completion_ratio": float(body.completion_ratio),
        "interruption_count": body.interruption_count,
        "stopped_early": body.stopped_early,
        "user_note": body.user_note,
    }


def is_successful_outcome(outcome: dict) -> bool:
    return (
        outcome.get("outcome_status") == OutcomeStatus.COMPLETED.value
        and Decimal(str(outcome.get("completion_ratio", 0))) >= Decimal("0.8")
    )
