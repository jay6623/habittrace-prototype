from pydantic import BaseModel, Field


class TrendPoint(BaseModel):
    label: str
    planned_mins: int
    completed_mins: int
    success_rate: float


class AnalyticsSummary(BaseModel):
    period: str  # "week" | "month" | "3months"
    total_tasks: int
    success_rate: float  # 0–100
    total_planned_minutes: int
    avg_importance: float
    avg_interruptions: float
    most_failed_category: str
    best_time_of_day: str
    failure_by_category: dict[str, int]
    failure_by_reason: dict[str, int]
    execution_trend: list[TrendPoint]
    success_by_hour: dict[str, float]  # "6-9 AM" -> 85.0


class TaskSummary(BaseModel):
    id: str
    title: str
    task_category: str
    task_status: str  # "pending" | "success" | "failed"
    planned_start_time: str
    planned_duration_min: int
    predicted_success: float | None = None  # ML predicted P(success), null if unavailable


class PlanHealth(BaseModel):
    overall_success_probability: float  # average predicted P(success) for today's tasks
    task_count: int
    risks: list[dict[str, str]]  # [{"level": "high", "title": ..., "detail": ...}]
    tasks: list[TaskSummary] = Field(default_factory=list)


class OutlookTask(BaseModel):
    id: str
    title: str
    success_probability: float
    predicted_failure_reason: str | None = None


class OutlookPersonalization(BaseModel):
    applied: bool
    sample_count: int
    confidence: float
    history_success_rate: float | None = None
    factors: list[dict] = Field(default_factory=list)


class PersonalizedOutlook(BaseModel):
    available: bool
    reason: str | None = None
    date: str | None = None
    task_count: int
    predicted_success_probability: float | None = None
    highest_potential: OutlookTask | None = None
    needs_attention: OutlookTask | None = None
    recommendation: dict | None = None
    personalization: OutlookPersonalization


class PersonalizedPattern(BaseModel):
    type: str
    label: str
    direction: str
    sample_count: int
    success_rate: float
    difference: float
    message: str


class PersonalizedInsights(BaseModel):
    available: bool
    reason: str | None = None
    period: str
    sample_count: int
    confidence_label: str
    success_rate: float | None = None
    previous_success_rate: float | None = None
    change_percentage_points: float | None = None
    strongest_pattern: PersonalizedPattern | None = None
    pattern_to_watch: PersonalizedPattern | None = None
    recommended_experiment: dict[str, str]
