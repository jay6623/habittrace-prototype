from pydantic import BaseModel
from typing import Optional


class ExecutionCreate(BaseModel):
    task_id: str
    actual_start_time: str
    actual_end_time: str
    interruption_count: int = 0
    stopped_early: bool = False
    task_status: str          # "success" | "failed"
    failure_reason: Optional[str] = None


class ExecutionResponse(BaseModel):
    id: str
    task_id: str
    user_id: str
    actual_start_time: str
    actual_end_time: str
    interruption_count: int
    stopped_early: bool
    task_status: str
    failure_reason: Optional[str]
    created_at: str
