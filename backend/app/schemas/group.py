"""Request and response contracts for group scheduling."""

from __future__ import annotations

import re
from datetime import date, time
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

INVITE_CODE_PATTERN = re.compile(r"^[A-Z0-9]{8}$")

GroupRole = Literal["owner", "admin", "member"]
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


class GroupMemberRoleUpdate(BaseModel):
    """Owner-only: promote a member to admin, or demote them back to member."""

    model_config = ConfigDict(extra="forbid")

    role: Literal["admin", "member"]


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
    avatar_url: str | None = None


class GroupTaskAssigneeResponse(BaseModel):
    user_id: str
    display_name: str | None = None
    avatar_url: str | None = None
    outcome: Literal["success", "failed"] | None = None


class GroupTaskCompletion(BaseModel):
    """The signed-in assignee logs only their own result."""

    model_config = ConfigDict(extra="forbid")

    outcome: Literal["success", "failed"]
    timezone: str = "UTC"

    @field_validator("timezone")
    @classmethod
    def _timezone(cls, value: str) -> str:
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

        name = value.strip() or "UTC"
        try:
            ZoneInfo(name)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("timezone must be a valid IANA timezone name") from exc
        return name


class GroupTaskCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(..., min_length=1, max_length=200)
    category: str = Field("Other", min_length=1, max_length=40)
    priority: GroupTaskPriority = "medium"
    due_date: date | None = None
    due_time: time | None = None
    assigned_to: UUID | None = None
    assigned_to_ids: list[UUID] = Field(default_factory=list, max_length=100)

    @field_validator("assigned_to_ids")
    @classmethod
    def _unique_assignees(cls, value: list[UUID]) -> list[UUID]:
        if len(value) != len(set(value)):
            raise ValueError("assigned_to_ids must not contain duplicates")
        return value

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
    assigned_to_ids: list[UUID] | None = Field(None, max_length=100)

    @field_validator("assigned_to_ids")
    @classmethod
    def _unique_assignees(cls, value: list[UUID] | None) -> list[UUID] | None:
        if value is not None and len(value) != len(set(value)):
            raise ValueError("assigned_to_ids must not contain duplicates")
        return value

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
    assigned_to_ids: list[str] = Field(default_factory=list)
    assignees: list[GroupTaskAssigneeResponse] = Field(default_factory=list)
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


class GroupAnnouncementCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(..., min_length=1, max_length=120)
    body: str = Field(..., min_length=1, max_length=2000)

    @field_validator("title")
    @classmethod
    def _strip_title(cls, value: str) -> str:
        return _require_non_blank(value, "title")

    @field_validator("body")
    @classmethod
    def _strip_body(cls, value: str) -> str:
        return _require_non_blank(value, "body")


class GroupAnnouncementReplyCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    body: str = Field(..., min_length=1, max_length=2000)

    @field_validator("body")
    @classmethod
    def _strip_body(cls, value: str) -> str:
        return _require_non_blank(value, "body")


class GroupAnnouncementReplyResponse(BaseModel):
    id: str
    announcement_id: str
    group_id: str
    author_id: str
    author_name: str | None = None
    author_role: GroupRole | None = None
    author_avatar_url: str | None = None
    body: str
    created_at: str


class GroupAnnouncementResponse(BaseModel):
    id: str
    group_id: str
    author_id: str
    author_name: str | None = None
    author_role: GroupRole | None = None
    author_avatar_url: str | None = None
    title: str
    body: str
    created_at: str
    replies: list[GroupAnnouncementReplyResponse] = Field(default_factory=list)
