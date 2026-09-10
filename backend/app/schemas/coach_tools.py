"""Provider-neutral contracts for read-only AI Coach tools."""

from __future__ import annotations

from datetime import date
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ToolDefinition(BaseModel):
    """A provider-neutral tool description exposed to the LLM."""

    name: str
    description: str
    input_schema: dict[str, Any]


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
