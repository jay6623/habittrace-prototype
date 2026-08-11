"""Request and response contracts for immutable AI plan inputs."""
from __future__ import annotations

from decimal import Decimal
from enum import Enum
from uuid import UUID

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from ..utils.timezone import get_timezone


class PlanInputSource(str, Enum):
    USER = "user"
    RESCHEDULE = "reschedule"


class PlanInputCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    parent_plan_input_id: UUID | None = None
    input_source: PlanInputSource = PlanInputSource.USER
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=5000)
    category: str = Field(min_length=1, max_length=100)
    planned_start: AwareDatetime
    planned_duration_minutes: int = Field(ge=1, le=10080)
    deadline_at: AwareDatetime | None = None
    importance: int = Field(default=3, ge=1, le=5)
    difficulty: int = Field(default=3, ge=1, le=5)
    required_energy: int = Field(default=3, ge=1, le=5)
    required_focus: int = Field(default=3, ge=1, le=5)
    current_energy: int | None = Field(default=None, ge=1, le=5)
    current_focus: int | None = Field(default=None, ge=1, le=5)
    sleep_hours: Decimal | None = Field(default=None, ge=0, le=24, decimal_places=2)
    stress_level: int | None = Field(default=None, ge=1, le=5)
    timezone_name: str = Field(default="UTC", min_length=1, max_length=100)
    is_fixed_time: bool = False

    @field_validator("title", "category")
    @classmethod
    def strip_required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value

    @field_validator("description")
    @classmethod
    def normalize_description(cls, value: str | None) -> str | None:
        if value is None:
            return None
        value = value.strip()
        return value or None

    @field_validator("timezone_name")
    @classmethod
    def validate_timezone_name(cls, value: str) -> str:
        value = value.strip()
        get_timezone(value)
        return value

    @model_validator(mode="after")
    def validate_time_window(self) -> PlanInputCreate:
        if self.deadline_at is not None and self.deadline_at < self.planned_start:
            raise ValueError("deadline_at must be at or after planned_start")
        return self


class PlanInputResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    user_id: UUID
    parent_plan_input_id: UUID | None
    input_source: str
    title: str
    description: str | None
    category: str
    planned_start: AwareDatetime
    planned_duration_minutes: int
    deadline_at: AwareDatetime | None
    importance: int
    difficulty: int
    required_energy: int
    required_focus: int
    current_energy: int | None
    current_focus: int | None
    sleep_hours: Decimal | None
    stress_level: int | None
    tasks_before_count: int
    planned_minutes_before: int
    daily_planned_minutes: int
    minutes_since_previous: int | None
    timezone_name: str
    is_fixed_time: bool
    created_at: AwareDatetime


def plan_input_to_insert(
    body: PlanInputCreate,
    *,
    user_id: UUID,
    tasks_before_count: int,
    planned_minutes_before: int,
    daily_planned_minutes: int,
    minutes_since_previous: int | None,
) -> dict:
    """Build a JSON-safe database payload without accepting server-owned fields."""
    return {
        "user_id": str(user_id),
        "parent_plan_input_id": (
            str(body.parent_plan_input_id) if body.parent_plan_input_id else None
        ),
        "input_source": body.input_source.value,
        "title": body.title,
        "description": body.description,
        "category": body.category,
        "planned_start": body.planned_start.isoformat(),
        "planned_duration_minutes": body.planned_duration_minutes,
        "deadline_at": body.deadline_at.isoformat() if body.deadline_at else None,
        "importance": body.importance,
        "difficulty": body.difficulty,
        "required_energy": body.required_energy,
        "required_focus": body.required_focus,
        "current_energy": body.current_energy,
        "current_focus": body.current_focus,
        "sleep_hours": float(body.sleep_hours) if body.sleep_hours is not None else None,
        "stress_level": body.stress_level,
        "tasks_before_count": tasks_before_count,
        "planned_minutes_before": planned_minutes_before,
        "daily_planned_minutes": daily_planned_minutes,
        "minutes_since_previous": minutes_since_previous,
        "timezone_name": body.timezone_name,
        "is_fixed_time": body.is_fixed_time,
    }
