from pydantic import BaseModel, Field


class PredictRequest(BaseModel):
    task_category: str
    planned_start_time: str  # "2:00 PM" or "14:00"
    planned_date: str | None = None  # ISO date; defaults to today server-side
    planned_duration_min: int = Field(..., ge=1, le=720)
    importance: int = Field(..., ge=1, le=5)
    energy_level: int = Field(..., ge=1, le=5)
    focus_level: int = Field(..., ge=1, le=5)
    total_tasks_today: int = Field(..., ge=1)
    user_id: str | None = None  # enables per-user calibration


class FeatureContribution(BaseModel):
    feature: str
    contribution: float
    value: float


class PredictResponse(BaseModel):
    success_probability: float
    personalized: bool
    predicted_failure_reason: str | None
    failure_probabilities: dict[str, float]
    top_positive_factors: list[FeatureContribution]
    top_negative_factors: list[FeatureContribution]
