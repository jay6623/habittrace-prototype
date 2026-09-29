"""Contracts for AI-assisted, draft-first daily schedule generation."""

from __future__ import annotations

from datetime import date, datetime, time
from typing import Literal
from uuid import UUID, uuid4

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator

from ..utils.timezone import get_timezone


class DailyScheduleTaskInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_id: UUID = Field(default_factory=uuid4)
    title: str = Field(min_length=1, max_length=200)
    estimated_duration_minutes: int = Field(ge=5, le=480)
    deadline_at: AwareDatetime | None = None
    importance: int = Field(ge=1, le=5)
    # Category is a trained categorical model feature, so generated schedules
    # must not silently collapse missing values into a generic fallback.
    category: str = Field(min_length=1, max_length=100)
    difficulty: int = Field(default=3, ge=1, le=5)
    required_energy: int = Field(default=3, ge=1, le=5)
    required_focus: int = Field(default=3, ge=1, le=5)
    is_fixed_time: bool = False
    fixed_start: AwareDatetime | None = None

    @field_validator("title", "category")
    @classmethod
    def strip_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be blank")
        return value

    @model_validator(mode="after")
    def validate_fixed_time(self) -> DailyScheduleTaskInput:
        if self.is_fixed_time and self.fixed_start is None:
            raise ValueError("fixed_start is required for a fixed-time task")
        if not self.is_fixed_time and self.fixed_start is not None:
            raise ValueError("fixed_start is only valid for a fixed-time task")
        return self


class DailyScheduleGenerate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    selected_date: date
    timezone_name: str = Field(default="UTC", min_length=1, max_length=100)
    day_start: time = time(8, 0)
    day_end: time = time(22, 0)
    minimum_buffer_minutes: int = Field(default=15, ge=0, le=120)
    slot_interval_minutes: int = Field(default=15, ge=5, le=60)
    max_planned_minutes: int = Field(default=480, ge=30, le=960)
    max_focus_block_minutes: int = Field(default=120, ge=30, le=480)
    tasks: list[DailyScheduleTaskInput] = Field(min_length=1, max_length=50)

    @field_validator("timezone_name")
    @classmethod
    def validate_timezone(cls, value: str) -> str:
        value = value.strip()
        get_timezone(value)
        return value

    @model_validator(mode="after")
    def validate_day(self) -> DailyScheduleGenerate:
        if self.day_start >= self.day_end:
            raise ValueError("day_end must be after day_start")
        if len({task.client_id for task in self.tasks}) != len(self.tasks):
            raise ValueError("task client_id values must be unique")
        return self


class DailyScheduledTask(BaseModel):
    model_config = ConfigDict(extra="ignore")

    task_id: UUID
    title: str
    estimated_duration_minutes: int
    deadline_at: AwareDatetime | None = None
    importance: int
    category: str
    difficulty: int
    required_energy: int
    required_focus: int
    is_fixed_time: bool
    scheduled_start: AwareDatetime
    scheduled_end: AwareDatetime
    predicted_success_probability: float = Field(ge=0, le=1)
    final_score: float
    explanation: str
    created_task_id: UUID | None = None
    plan_input_id: UUID | None = None


class DailyUnscheduledTask(BaseModel):
    model_config = ConfigDict(extra="ignore")

    task_id: UUID
    title: str
    estimated_duration_minutes: int
    reason: str


class DailyScheduleResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    user_id: UUID
    selected_date: date
    timezone_name: str
    day_start: time
    day_end: time
    minimum_buffer_minutes: int
    slot_interval_minutes: int
    max_planned_minutes: int
    max_focus_block_minutes: int
    status: Literal["draft", "confirmed"]
    scheduled_tasks: list[DailyScheduledTask]
    unscheduled_tasks: list[DailyUnscheduledTask]
    warnings: list[str] = Field(default_factory=list)
    created_at: datetime
    confirmed_at: datetime | None = None


class DailyScheduleAdjustment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    task_id: UUID
    scheduled_start: AwareDatetime


class DailyScheduleUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    adjustments: list[DailyScheduleAdjustment] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def validate_unique_tasks(self) -> DailyScheduleUpdate:
        if len({item.task_id for item in self.adjustments}) != len(self.adjustments):
            raise ValueError("each task may be adjusted only once")
        return self
