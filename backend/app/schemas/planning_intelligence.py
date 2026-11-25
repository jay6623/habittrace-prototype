"""Explicit personal decisions and opt-in shared project planning."""

from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from ..utils.timezone import get_timezone


class ComparePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")
    task_id: UUID
    remaining_minutes: int | None = Field(default=None, ge=1, le=720)
    expected_energy: int = Field(default=3, ge=1, le=5)
    expected_focus: int = Field(default=3, ge=1, le=5)


class ChoosePlan(BaseModel):
    model_config = ConfigDict(extra="forbid")
    option_id: str = Field(pattern="^(current|move|buffer|split)$")
    confirmed: Literal[True]


class ProjectMilestone(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=120)
    due_date: date
    task_ids: list[UUID] = Field(default_factory=list, max_length=100)
    completion_criteria: str = Field(min_length=1, max_length=500)
    timezone_name: str = "UTC"

    @field_validator("timezone_name")
    @classmethod
    def valid_timezone(cls, value):
        get_timezone(value)
        return value


class ProjectDependency(BaseModel):
    model_config = ConfigDict(extra="forbid")
    task_id: UUID
    predecessor_id: UUID


class SharedCapacity(BaseModel):
    model_config = ConfigDict(extra="forbid")
    minutes_per_day: int | None = Field(default=None, ge=0, le=720)
    available_until: date | None = None


class SharedRemaining(BaseModel):
    model_config = ConfigDict(extra="forbid")
    remaining_minutes: int | None = Field(default=None, ge=0, le=10080)


class HelpRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    task_id: UUID
    helper_id: UUID
    message: str = Field(min_length=1, max_length=300)


class HelpReply(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["accepted", "declined"]


class ProjectTimezone(BaseModel):
    model_config = ConfigDict(extra="forbid")
    timezone_name: str = Field(min_length=1, max_length=100)

    @field_validator("timezone_name")
    @classmethod
    def valid_timezone(cls, value):
        get_timezone(value)
        return value
