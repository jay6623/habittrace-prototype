"""Contracts for deterministic candidate generation and AI time scoring."""
from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator


class TimeRecommendationCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    earliest_start: AwareDatetime
    latest_end: AwareDatetime
    slot_interval_minutes: int = Field(default=30, ge=5, le=240)
    minimum_buffer_minutes: int = Field(default=15, ge=0, le=1440)

    @model_validator(mode="after")
    def validate_window(self) -> TimeRecommendationCreate:
        if self.earliest_start >= self.latest_end:
            raise ValueError("latest_end must be after earliest_start")
        return self


class TimeCandidateResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    recommendation_id: UUID
    candidate_start: AwareDatetime
    candidate_end: AwareDatetime
    predicted_success_probability: float
    conflict_penalty: float
    overload_penalty: float
    preference_penalty: float
    final_score: float
    rank: int
    reason_snapshot: dict


class TimeRecommendationResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: UUID
    plan_input_id: UUID
    model_version_id: UUID
    earliest_start: AwareDatetime
    latest_end: AwareDatetime
    slot_interval_minutes: int
    minimum_buffer_minutes: int
    status: str
    selected_candidate_id: UUID | None
    created_at: datetime
    candidates: list[TimeCandidateResponse]


class TimeRecommendationSelect(BaseModel):
    model_config = ConfigDict(extra="forbid")

    candidate_id: UUID
    status: Literal["accepted", "modified", "dismissed"] = "accepted"
