"""Group scheduling routes. All routes require a verified Supabase user."""

from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status

from ..config import settings
from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..rate_limit import RateLimitSpec, rate_limiter
from ..repositories.group_repository import GroupRepository
from ..repositories.personalization_repository import PersonalizationRepository
from ..schemas.group import (
    GroupAnnouncementCreate,
    GroupAnnouncementReplyCreate,
    GroupAnnouncementReplyResponse,
    GroupAnnouncementResponse,
    GroupCreate,
    GroupDetailResponse,
    GroupJoinRequest,
    GroupMemberResponse,
    GroupMemberRoleUpdate,
    GroupPersonalPlanRequest,
    GroupPersonalPreview,
    GroupResponse,
    GroupTaskCompletion,
    GroupTaskCreate,
    GroupTaskResponse,
    GroupTaskUpdate,
)
from ..schemas.task import TaskResponse
from ..services.ai_v2_ml_service import get_ai_v2_ml_service
from ..services.google_calendar_service import GoogleCalendarService
from ..services.group_personal_planning_service import GroupPersonalPlanningService
from ..services.group_service import GroupService
from ..services.personalization_service import PersonalizationService
from ..services.task_service import TaskService

router = APIRouter()


def get_group_service() -> GroupService:
    if not is_supabase_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Primary database is not configured.",
        )
    return GroupService(GroupRepository(get_supabase()))


GroupServiceDep = Annotated[GroupService, Depends(get_group_service)]


def get_group_personal_planning_service(groups: GroupServiceDep) -> GroupPersonalPlanningService:
    db = groups.groups.db
    return GroupPersonalPlanningService(
        groups,
        TaskService(db),
        get_ai_v2_ml_service(),
        PersonalizationService(PersonalizationRepository(db)),
        GoogleCalendarService(db),
    )


PersonalPlanningDep = Annotated[
    GroupPersonalPlanningService, Depends(get_group_personal_planning_service)
]


@router.post("/{group_id}/tasks/{task_id}/personal-preview", response_model=GroupPersonalPreview)
def preview_group_personal_plan(
    group_id: UUID,
    task_id: UUID,
    body: GroupPersonalPlanRequest,
    user_id: CurrentUserId,
    service: PersonalPlanningDep,
    response: Response,
):
    response.headers["Cache-Control"] = "no-store"
    rate_limiter.enforce(
        key=f"group-personal-preview:{user_id}",
        spec=RateLimitSpec(
            requests=settings.predict_requests_per_window,
            window_seconds=settings.rate_limit_window_seconds,
        ),
    )
    return service.preview(user_id, group_id, task_id, body)


@router.post("/{group_id}/tasks/{task_id}/personal-plan", response_model=TaskResponse)
def confirm_group_personal_plan(
    group_id: UUID,
    task_id: UUID,
    body: GroupPersonalPlanRequest,
    user_id: CurrentUserId,
    service: PersonalPlanningDep,
    response: Response,
):
    response.headers["Cache-Control"] = "no-store"
    return service.confirm(user_id, group_id, task_id, body)


@router.post("", response_model=GroupResponse, status_code=status.HTTP_201_CREATED)
def create_group(body: GroupCreate, user_id: CurrentUserId, service: GroupServiceDep):
    return service.create_group(user_id, body)


@router.get("", response_model=list[GroupResponse])
def list_groups(user_id: CurrentUserId, service: GroupServiceDep):
    return service.list_groups(user_id)


# Declared before "/{group_id}" so the literal path is matched first.
@router.post("/join", response_model=GroupResponse)
def join_group(body: GroupJoinRequest, user_id: CurrentUserId, service: GroupServiceDep):
    return service.join_group(user_id, body)


@router.get("/{group_id}", response_model=GroupDetailResponse)
def get_group(
    group_id: UUID,
    user_id: CurrentUserId,
    service: GroupServiceDep,
    timezone_name: str = Query("UTC", alias="timezone"),
):
    return service.get_group_detail(user_id, group_id, timezone_name)


@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(group_id: UUID, user_id: CurrentUserId, service: GroupServiceDep):
    service.delete_group(user_id, group_id)


@router.post("/{group_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_group(group_id: UUID, user_id: CurrentUserId, service: GroupServiceDep):
    service.leave_group(user_id, group_id)


@router.patch("/{group_id}/members/{target_user_id}", response_model=GroupMemberResponse)
def update_group_member_role(
    group_id: UUID,
    target_user_id: UUID,
    body: GroupMemberRoleUpdate,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.set_member_role(user_id, group_id, target_user_id, body)


@router.get(
    "/{group_id}/announcements",
    response_model=list[GroupAnnouncementResponse],
)
def list_group_announcements(group_id: UUID, user_id: CurrentUserId, service: GroupServiceDep):
    return service.list_announcements(user_id, group_id)


@router.post(
    "/{group_id}/announcements",
    response_model=GroupAnnouncementResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_group_announcement(
    group_id: UUID,
    body: GroupAnnouncementCreate,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.create_announcement(user_id, group_id, body)


@router.post(
    "/{group_id}/announcements/{announcement_id}/replies",
    response_model=GroupAnnouncementReplyResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_group_announcement_reply(
    group_id: UUID,
    announcement_id: UUID,
    body: GroupAnnouncementReplyCreate,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.create_reply(user_id, group_id, announcement_id, body)


@router.post(
    "/{group_id}/tasks",
    response_model=GroupTaskResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_group_task(
    group_id: UUID,
    body: GroupTaskCreate,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.create_task(user_id, group_id, body)


@router.post(
    "/{group_id}/tasks/{task_id}/completion",
    response_model=GroupTaskResponse,
)
def log_group_task_completion(
    group_id: UUID,
    task_id: UUID,
    body: GroupTaskCompletion,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.log_own_outcome(user_id, group_id, task_id, body)


@router.patch("/{group_id}/tasks/{task_id}", response_model=GroupTaskResponse)
def update_group_task(
    group_id: UUID,
    task_id: UUID,
    body: GroupTaskUpdate,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    return service.update_task(user_id, group_id, task_id, body)


@router.delete("/{group_id}/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group_task(
    group_id: UUID,
    task_id: UUID,
    user_id: CurrentUserId,
    service: GroupServiceDep,
):
    service.delete_task(user_id, group_id, task_id)
