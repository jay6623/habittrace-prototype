"""Group scheduling routes. All routes require a verified Supabase user."""

from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from ..db.supabase_client import get_supabase, is_supabase_configured
from ..dependencies.auth import CurrentUserId
from ..repositories.group_repository import GroupRepository
from ..schemas.group import (
    GroupCreate,
    GroupDetailResponse,
    GroupJoinRequest,
    GroupResponse,
    GroupTaskCreate,
    GroupTaskResponse,
    GroupTaskUpdate,
)
from ..services.group_service import GroupService

router = APIRouter()


def get_group_service() -> GroupService:
    if not is_supabase_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Primary database is not configured.",
        )
    return GroupService(GroupRepository(get_supabase()))


GroupServiceDep = Annotated[GroupService, Depends(get_group_service)]


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
def get_group(group_id: UUID, user_id: CurrentUserId, service: GroupServiceDep):
    return service.get_group_detail(user_id, group_id)


@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(group_id: UUID, user_id: CurrentUserId, service: GroupServiceDep):
    service.delete_group(user_id, group_id)


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
