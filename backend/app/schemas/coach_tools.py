"""Provider-neutral contracts for AI Coach tools."""

from __future__ import annotations

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ToolDefinition(BaseModel):
    """A provider-neutral tool description exposed to the LLM."""

    name: str
    description: str
    input_schema: dict[str, Any]
    kind: Literal["read", "proposal"] = "read"


class ToolCall(BaseModel):
    """A tool request proposed by the LLM. The backend still validates arguments."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=100)
    arguments: dict[str, Any] = Field(default_factory=dict)


class ToolDecision(BaseModel):
    """Zero calls means the coach can answer without loading HabitTrace data."""

    model_config = ConfigDict(extra="forbid")

    calls: list[ToolCall] = Field(default_factory=list, max_length=4)


class ToolResult(BaseModel):
    name: str
    ok: bool
    data: dict[str, Any] | None = None
    error: str | None = None
    proposal: dict[str, Any] | None = None


class TaskDataScope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: Literal["Study", "Work", "Exercise", "Personal", "Other"] | None = None
    title_query: str | None = Field(default=None, min_length=1, max_length=100)
    period_days: int = Field(default=30, ge=7, le=90)


class GetTaskPerformanceArgs(TaskDataScope):
    compare_previous_period: bool = False
    group_by: list[Literal["hour", "weekday"]] = Field(default_factory=list, max_length=2)


class GetFailurePatternsArgs(TaskDataScope):
    pass


class GetScheduleArgs(BaseModel):
    model_config = ConfigDict(extra="forbid")

    start_date: date
    end_date: date

    @model_validator(mode="after")
    def validate_range(self) -> GetScheduleArgs:
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        if (self.end_date - self.start_date).days > 31:
            raise ValueError("schedule ranges cannot exceed 31 days")
        return self


class GetUserPreferencesArgs(BaseModel):
    model_config = ConfigDict(extra="forbid")


class FindAvailableTimesArgs(BaseModel):
    """Validated inputs for information-only suggestions or a task proposal."""

    model_config = ConfigDict(extra="forbid")

    mode: Literal["suggest_times", "create_task_proposal"]
    planned_date: date | None = None
    duration_minutes: int | None = Field(default=None, ge=5, le=720)
    title: str | None = Field(default=None, min_length=1, max_length=200)
    category: Literal["Study", "Work", "Exercise", "Personal", "Other"] = "Other"
    exact_time: str | None = Field(default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    earliest_time: str | None = Field(default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    latest_time: str | None = Field(default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    importance: int = Field(default=3, ge=1, le=5)
    energy_level: int = Field(default=3, ge=1, le=5)
    focus_level: int = Field(default=3, ge=1, le=5)

    @model_validator(mode="after")
    def validate_time_constraints(self) -> FindAvailableTimesArgs:
        if self.exact_time and (self.earliest_time or self.latest_time):
            raise ValueError("exact_time cannot be combined with a time window")
        if bool(self.earliest_time) != bool(self.latest_time):
            raise ValueError("earliest_time and latest_time must be supplied together")
        if self.earliest_time and self.latest_time and self.earliest_time >= self.latest_time:
            raise ValueError("latest_time must be after earliest_time")
        return self
