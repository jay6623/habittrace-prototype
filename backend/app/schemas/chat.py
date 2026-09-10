from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .task import TaskCreate


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    message: str
    history: list[ChatMessage] = []
    conversation_id: UUID | None = None
    timezone_name: str = Field(default="UTC", min_length=1, max_length=100)


class PlanDraft(BaseModel):
    model_config = ConfigDict(extra="ignore")

    title: str | None = None
    category: Literal["Study", "Work", "Exercise", "Personal", "Other"] = "Other"
    planned_date: str | None = None
    duration_minutes: int = Field(default=60, ge=5, le=720)
    exact_time: str | None = None
    earliest_time: str | None = None
    latest_time: str | None = None
    importance: int = Field(default=3, ge=1, le=5)
    energy_level: int = Field(default=3, ge=1, le=5)
    focus_level: int = Field(default=3, ge=1, le=5)


class PreferenceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    preferred_day_start: str | None = Field(
        default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$"
    )
    preferred_day_end: str | None = Field(
        default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$"
    )
    minimum_buffer_minutes: int | None = Field(default=None, ge=0, le=240)
    coaching_style: Literal["supportive", "direct", "analytical"] | None = None

    @model_validator(mode="after")
    def validate_update(self) -> PreferenceUpdate:
        if not self.model_fields_set or all(
            getattr(self, field_name) is None for field_name in self.model_fields_set
        ):
            raise ValueError("at least one preference value is required")
        if (
            self.preferred_day_start
            and self.preferred_day_end
            and self.preferred_day_start >= self.preferred_day_end
        ):
            raise ValueError("preferred_day_end must be after preferred_day_start")
        return self


class ProposalConfirmRequest(BaseModel):
    candidate_start: str | None = None
    task: TaskCreate | None = None


class TimeOption(BaseModel):
    start: str
    end: str
    score: float
    reasons: list[str]
