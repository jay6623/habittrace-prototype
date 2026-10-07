from datetime import date, datetime
from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator

from ..utils.timezone import get_timezone


class TaskPlanningFields(BaseModel):
    @field_validator("title", "task_category", check_fields=False)
    @classmethod
    def normalize_required_text(cls, value: str | None) -> str:
        if value is None or not value.strip():
            raise ValueError("must not be blank")
        return value.strip()

    @field_validator("planned_start_time", check_fields=False)
    @classmethod
    def validate_start_time(cls, value: str | None) -> str | None:
        if value is None:
            raise ValueError("planned_start_time cannot be null")
        for pattern in ("%I:%M %p", "%I:%M%p", "%H:%M", "%H:%M:%S"):
            try:
                datetime.strptime(value.strip().upper(), pattern)
                return value.strip().upper()
            except ValueError:
                continue
        raise ValueError("Invalid planned_start_time")

    @field_validator("planned_date", check_fields=False)
    @classmethod
    def validate_planned_date(cls, value: str | None) -> str | None:
        return date.fromisoformat(value).isoformat() if value is not None else None

    @field_validator("timezone_name", check_fields=False)
    @classmethod
    def validate_timezone(cls, value: str | None) -> str:
        if value is None:
            raise ValueError("timezone_name cannot be null")
        get_timezone(value)
        return value


class TaskCreate(TaskPlanningFields):
    title: str = Field(..., min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=2000)
    task_category: str = Field(min_length=1, max_length=100)
    planned_start_time: str  # "2:00 PM" or "14:00"
    planned_date: str | None = None  # ISO date "2024-01-15"; defaults to today
    planned_duration_min: int = Field(..., ge=1, le=720)
    importance: int = Field(..., ge=1, le=5)
    energy_level: int = Field(..., ge=1, le=5)
    focus_level: int = Field(..., ge=1, le=5)
    total_tasks_today: int = Field(..., ge=1)
    timezone_name: str = "UTC"

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class TaskUpdate(TaskPlanningFields):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    notes: str | None = Field(default=None, max_length=2000)
    task_category: str | None = Field(default=None, min_length=1, max_length=100)
    planned_start_time: str | None = None
    planned_date: str | None = None
    planned_duration_min: int | None = Field(None, ge=1, le=720)
    importance: int | None = Field(None, ge=1, le=5)
    energy_level: int | None = Field(None, ge=1, le=5)
    focus_level: int | None = Field(None, ge=1, le=5)
    timezone_name: str | None = None

    @model_validator(mode="before")
    @classmethod
    def reject_null_planning_fields(cls, value: Any) -> Any:
        if isinstance(value, dict):
            for key in cls.model_fields:
                if key != "notes" and key in value and value[key] is None:
                    raise ValueError(f"{key} cannot be null")
        return value

    @field_validator("notes")
    @classmethod
    def normalize_notes(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class TaskResponse(BaseModel):
    id: str
    user_id: str
    title: str
    notes: str | None = None
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
    timezone_name: str = "UTC"
    ai_plan_input_id: str | None = None
    ai_sync_status: str = "unlinked"

    @model_validator(mode="after")
    def hide_undelivered_plan_id(self) -> "TaskResponse":
        if self.ai_sync_status != "synced":
            self.ai_plan_input_id = None
        return self

    # ML prediction (populated by /predict, optionally attached on create)
    prediction: dict | None = None
