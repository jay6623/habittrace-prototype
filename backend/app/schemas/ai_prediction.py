"""Request and response contracts for V2 offline-trained predictions."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from .ai_plan import PlanInputCreate


class AIPredictRequest(PlanInputCreate):
    """Plan-time fields plus optional schedule context for inference."""

    tasks_before_count: int = Field(default=0, ge=0)
    planned_minutes_before: int = Field(default=0, ge=0)
    daily_planned_minutes: int = Field(default=0, ge=0)
    minutes_since_previous: int | None = Field(default=None, ge=0)


class AIPredictResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model_version: str
    success_probability: float = Field(ge=0, le=1)
    failure_reason_probabilities: dict[str, float]
    predicted_failure_reason: str | None
    predicted_at: datetime
    explanation: dict
    recommended_actions: list[dict]


def prediction_payload(body: AIPredictRequest) -> dict[str, Any]:
    """Create the database-shaped plan row used by the feature builder."""

    values = body.model_dump(mode="json")
    values["id"] = "prediction-input"
    values["created_at"] = datetime.now().astimezone().isoformat()
    return values
