from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ExecutionCreate(BaseModel):
    task_id: str
    actual_start_time: str = Field(..., min_length=1)
    actual_end_time: str = Field(..., min_length=1)
    interruption_count: int = Field(default=0, ge=0)
    stopped_early: bool = False
    task_status: Literal["success", "failed"]
    failure_reason: str | None = Field(default=None, max_length=100)


class ExecutionStart(BaseModel):
    task_id: str


class ExecutionComplete(BaseModel):
    interruption_count: int = Field(default=0, ge=0)
    stopped_early: bool = False
    task_status: Literal["success", "failed"]
    failure_reason: str | None = Field(default=None, max_length=100)

    @model_validator(mode="after")
    def validate_failure_reason(self) -> "ExecutionComplete":
        if self.task_status == "failed" and not (self.failure_reason or "").strip():
            raise ValueError("failure_reason is required for a failed execution")
        if self.task_status == "success":
            self.failure_reason = None
        elif self.failure_reason is not None:
            self.failure_reason = self.failure_reason.strip()
        return self


class ExecutionResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    actual_start_time: str
    actual_end_time: str | None
    interruption_count: int
    stopped_early: bool
    task_status: Literal["success", "failed"] | None
    failure_reason: str | None
    created_at: str
