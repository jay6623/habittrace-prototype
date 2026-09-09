"""Request and response contracts for group scheduling."""

from __future__ import annotations

import re
from datetime import date, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

INVITE_CODE_PATTERN = re.compile(r"^[A-Z0-9]{8}$")

GroupRole = Literal["owner", "member"]
GroupTaskStatus = Literal["pending", "success", "failed"]
GroupTaskPriority = Literal["high", "medium", "low"]


def _require_non_blank(value: str, field_name: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError(f"{field_name} must not be blank")
    return stripped


class GroupCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(..., min_length=1, max_length=80)

    @field_validator("name")
    @classmethod
    def _strip_name(cls, value: str) -> str:
        return _require_non_blank(value, "name")


class GroupJoinRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    invite_code: str = Field(..., min_length=1, max_length=32)

    @field_validator("invite_code")
    @classmethod
    def _normalize_invite_code(cls, value: str) -> str:
        normalized = value.strip().upper()
        if not INVITE_CODE_PATTERN.fullmatch(normalized):
            raise ValueError("invite_code must be 8 letters or digits")
        return normalized


class GroupResponse(BaseModel):
    id: str
    owner_id: str
    name: str
    invite_code: str
    created_at: str
    role: GroupRole


class GroupMemberResponse(BaseModel):
    user_id: str
    role: GroupRole
    joined_at: str
    display_name: str | None = None


class GroupTaskCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(..., min_length=1, max_length=200)
    category: str = Field("Other", min_length=1, max_length=40)
    priority: GroupTaskPriority = "medium"
    due_date: date | None = None
    due_time: time | None = None
    assigned_to: UUID | None = None

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str) -> str:
        return _require_non_blank(value, "title")

    @field_validator("category")
    @classmethod
    def _strip_category(cls, value: str) -> str:
        return _require_non_blank(value, "category")


class GroupTaskUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = Field(None, min_length=1, max_length=200)
    category: str | None = Field(None, min_length=1, max_length=40)
    priority: GroupTaskPriority | None = None
    status: GroupTaskStatus | None = None
    due_date: date | None = None
    due_time: time | None = None
    assigned_to: UUID | None = None

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str | None) -> str | None:
        return None if value is None else _require_non_blank(value, "title")

    @field_validator("category")
    @classmethod
    def _strip_category(cls, value: str | None) -> str | None:
        return None if value is None else _require_non_blank(value, "category")


class GroupTaskResponse(BaseModel):
    id: str
    group_id: str
    created_by: str
    assigned_to: str | None = None
    assignee_name: str | None = None
    title: str
    category: str
    priority: GroupTaskPriority
    status: GroupTaskStatus
    due_date: str | None = None  # ISO date, e.g. "2026-09-05"
    due_time: str | None = None  # ISO time, e.g. "14:30:00"
    created_at: str
    updated_at: str


class GroupDetailResponse(BaseModel):
    group: GroupResponse
    members: list[GroupMemberResponse]
    tasks: list[GroupTaskResponse]
