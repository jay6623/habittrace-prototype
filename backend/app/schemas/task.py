from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=200)
    task_category: str
    planned_start_time: str  # "2:00 PM" or "14:00"
    planned_date: str | None = None  # ISO date "2024-01-15"; defaults to today
    planned_duration_min: int = Field(..., ge=1, le=720)
    importance: int = Field(..., ge=1, le=5)
    energy_level: int = Field(..., ge=1, le=5)
    focus_level: int = Field(..., ge=1, le=5)
    total_tasks_today: int = Field(..., ge=1)


class TaskUpdate(BaseModel):
    title: str | None = None
    task_category: str | None = None
    planned_start_time: str | None = None
    planned_date: str | None = None
    planned_duration_min: int | None = Field(None, ge=1, le=720)
    importance: int | None = Field(None, ge=1, le=5)
    energy_level: int | None = Field(None, ge=1, le=5)
    focus_level: int | None = Field(None, ge=1, le=5)


class TaskResponse(BaseModel):
    id: str
    user_id: str
    title: str
    task_category: str
    planned_start_time: str
    planned_date: str
    planned_duration_min: int
    importance: int
    energy_level: int
    focus_level: int
    total_tasks_today: int
    task_status: str  # "pending" | "success" | "failed"
    created_at: str

    # ML prediction (populated by /predict, optionally attached on create)
    prediction: dict | None = None
