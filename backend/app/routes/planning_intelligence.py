"""Personal decisions and shared project forecasting, each with its own privacy boundary."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response

from ..config import settings
from ..dependencies.auth import CurrentUserId
from ..rate_limit import RateLimitSpec, rate_limiter
from ..schemas.planning_intelligence import (
    ChoosePlan,
    ComparePlan,
    HelpReply,
    HelpRequest,
    ProjectDependency,
    ProjectMilestone,
    ProjectTimezone,
    SharedCapacity,
    SharedRemaining,
)
from ..services.planning_intelligence_service import PlanningIntelligenceService
from ..services.project_forecast_service import ProjectForecastService
from .groups import GroupServiceDep, PersonalPlanningDep

router = APIRouter(tags=["Planning decisions"])


def personal_service(planner: PersonalPlanningDep):
    return PlanningIntelligenceService(planner)


def project_service(groups: GroupServiceDep):
    return ProjectForecastService(groups)


Personal = Annotated[PlanningIntelligenceService, Depends(personal_service)]
Project = Annotated[ProjectForecastService, Depends(project_service)]


@router.post("/planning/compare")
def compare(body: ComparePlan, user_id: CurrentUserId, service: Personal, response: Response):
    response.headers["Cache-Control"] = "no-store"
    rate_limiter.enforce(
        key=f"planning-compare:{user_id}",
        spec=RateLimitSpec(
            requests=settings.predict_requests_per_window,
            window_seconds=settings.rate_limit_window_seconds,
        ),
    )
    return service.compare(user_id, body)


@router.post("/planning/comparisons/{comparison_id}/apply")
def choose(
    comparison_id: UUID,
    body: ChoosePlan,
    user_id: CurrentUserId,
    service: Personal,
    response: Response,
):
    response.headers["Cache-Control"] = "no-store"
    return service.choose(user_id, comparison_id, body.option_id)


@router.post("/planning/comparisons/{comparison_id}/viewed")
def viewed(comparison_id: UUID, user_id: CurrentUserId, service: Personal):
    return service.viewed(user_id, comparison_id)


@router.get("/planning/evaluation")
def evaluation(user_id: CurrentUserId, service: Personal, response: Response):
    response.headers["Cache-Control"] = "no-store"
    return service.evaluation(user_id)


@router.get("/groups/{group_id}/forecast")
def forecast(
    group_id: UUID,
    user_id: CurrentUserId,
    service: Project,
    timezone_name: str = Query("UTC", min_length=1, max_length=100),
):
    return service.forecast(user_id, group_id, timezone_name)


@router.post("/groups/{group_id}/dependencies")
def dependency(group_id: UUID, body: ProjectDependency, user_id: CurrentUserId, service: Project):
    return service.dependency(user_id, group_id, body)


@router.delete("/groups/{group_id}/dependencies")
def remove_dependency(
    group_id: UUID, body: ProjectDependency, user_id: CurrentUserId, service: Project
):
    return service.dependency(user_id, group_id, body, remove=True)


@router.post("/groups/{group_id}/milestones")
def milestone(group_id: UUID, body: ProjectMilestone, user_id: CurrentUserId, service: Project):
    return service.milestone(user_id, group_id, body)


@router.post("/groups/{group_id}/milestones/{milestone_id}/confirm")
def confirm_milestone(group_id: UUID, milestone_id: UUID, user_id: CurrentUserId, service: Project):
    return service.confirm_milestone(user_id, group_id, milestone_id)


@router.patch("/groups/{group_id}/my-capacity")
def capacity(group_id: UUID, body: SharedCapacity, user_id: CurrentUserId, service: Project):
    return service.capacity(user_id, group_id, body)


@router.patch("/groups/{group_id}/tasks/{task_id}/my-remaining-work")
def remaining(
    group_id: UUID, task_id: UUID, body: SharedRemaining, user_id: CurrentUserId, service: Project
):
    return service.remaining(user_id, group_id, task_id, body)


@router.post("/groups/{group_id}/help-requests")
def request_help(group_id: UUID, body: HelpRequest, user_id: CurrentUserId, service: Project):
    return service.help(user_id, group_id, body)


@router.patch("/groups/{group_id}/help-requests/{request_id}")
def reply_help(
    group_id: UUID, request_id: UUID, body: HelpReply, user_id: CurrentUserId, service: Project
):
    return service.reply(user_id, group_id, request_id, body)


@router.patch("/groups/{group_id}/planning-timezone")
def project_timezone(
    group_id: UUID, body: ProjectTimezone, user_id: CurrentUserId, service: Project
):
    return service.project_timezone(user_id, group_id, body)


@router.patch("/groups/{group_id}/milestones/{milestone_id}")
def edit_milestone(
    group_id: UUID,
    milestone_id: UUID,
    body: ProjectMilestone,
    user_id: CurrentUserId,
    service: Project,
):
    return service.edit_milestone(user_id, group_id, milestone_id, body)


@router.delete("/groups/{group_id}/milestones/{milestone_id}")
def remove_milestone(group_id: UUID, milestone_id: UUID, user_id: CurrentUserId, service: Project):
    return service.edit_milestone(user_id, group_id, milestone_id)
