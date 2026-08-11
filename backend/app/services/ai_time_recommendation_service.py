"""Hybrid time recommendations: hard constraints plus AI success scoring."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any
from uuid import UUID

from ..core.errors import DomainValidationError, ResourceNotFoundError
from ..repositories.ai_plan_repository import AIPlanRepository
from ..repositories.ai_time_recommendation_repository import (
    AITimeRecommendationRepository,
)
from ..schemas.ai_time_recommendation import (
    TimeRecommendationCreate,
    TimeRecommendationSelect,
)
from ..utils.timezone import as_local
from .ai_prediction_service import AIPredictionService
from .ai_v2_ml_service import AIV2MLService


def _parse_datetime(value: object) -> datetime:
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise DomainValidationError("The database returned a naive plan timestamp.")
    return parsed


class AITimeRecommendationService:
    def __init__(
        self,
        plans: AIPlanRepository,
        recommendations: AITimeRecommendationRepository,
        predictions: AIPredictionService,
        model_service: AIV2MLService,
    ) -> None:
        self.plans = plans
        self.recommendations = recommendations
        self.predictions = predictions
        self.model_service = model_service

    def create(
        self,
        user_id: UUID,
        plan_input_id: UUID,
        body: TimeRecommendationCreate,
    ) -> dict:
        plan = self.plans.get_owned(plan_input_id, user_id)
        if plan is None:
            raise ResourceNotFoundError("Plan not found.")
        if not self.model_service.is_ready:
            raise RuntimeError("AI V2 model artifacts are not loaded")

        scored = self._score_candidates(user_id, plan, body)
        if not scored:
            raise DomainValidationError(
                "No conflict-free time candidates are available in the requested window."
            )

        model_version = self.predictions.ensure_model_version(
            "success", self.model_service.model_version
        )
        recommendation = self.recommendations.create_recommendation(
            {
                "plan_input_id": str(plan_input_id),
                "model_version_id": model_version["id"],
                "earliest_start": body.earliest_start.isoformat(),
                "latest_end": body.latest_end.isoformat(),
                "slot_interval_minutes": body.slot_interval_minutes,
                "minimum_buffer_minutes": body.minimum_buffer_minutes,
                "status": "generated",
                "selected_candidate_id": None,
            }
        )
        candidate_payloads = [
            {
                "recommendation_id": recommendation["id"],
                **candidate,
            }
            for candidate in scored
        ]
        candidates = self.recommendations.create_candidates(candidate_payloads)
        return {**recommendation, "candidates": candidates}

    def get(self, user_id: UUID, recommendation_id: UUID) -> dict:
        recommendation = self.recommendations.get_recommendation(recommendation_id)
        if recommendation is None:
            raise ResourceNotFoundError("Time recommendation not found.")
        plan_id = UUID(str(recommendation["plan_input_id"]))
        if self.plans.get_owned(plan_id, user_id) is None:
            raise ResourceNotFoundError("Time recommendation not found.")
        return {
            **recommendation,
            "candidates": self.recommendations.get_candidates(recommendation_id),
        }

    def select(
        self,
        user_id: UUID,
        recommendation_id: UUID,
        body: TimeRecommendationSelect,
    ) -> dict:
        recommendation = self.recommendations.get_recommendation(recommendation_id)
        if recommendation is None:
            raise ResourceNotFoundError("Time recommendation not found.")
        plan_id = UUID(str(recommendation["plan_input_id"]))
        if self.plans.get_owned(plan_id, user_id) is None:
            raise ResourceNotFoundError("Time recommendation not found.")
        candidates = self.recommendations.get_candidates(recommendation_id)
        if not any(str(candidate.get("id")) == str(body.candidate_id) for candidate in candidates):
            raise ResourceNotFoundError("Time candidate not found.")
        updated = self.recommendations.select_candidate(
            recommendation_id, body.candidate_id, body.status
        )
        return {
            **recommendation,
            **updated,
            "candidates": candidates,
        }

    def _score_candidates(
        self,
        user_id: UUID,
        plan: dict[str, Any],
        body: TimeRecommendationCreate,
    ) -> list[dict]:
        duration = timedelta(minutes=int(plan["planned_duration_minutes"]))
        latest_start = body.latest_end - duration
        if body.earliest_start > latest_start:
            return []

        rows = self.plans.list_schedule_rows(user_id)
        excluded_ids = self._revision_chain_ids(plan, rows)
        schedule = [
            row
            for row in rows
            if str(row.get("id")) not in excluded_ids
        ]
        candidates: list[dict] = []
        current = body.earliest_start
        while current <= latest_start:
            end = current + duration
            if not self._conflicts(current, end, schedule, body.minimum_buffer_minutes):
                context = self._schedule_context(current, plan, schedule)
                scored_plan = {**plan, "planned_start": current.isoformat(), **context}
                result = self.model_service.predict(scored_plan)
                daily_planned_minutes = int(context["daily_planned_minutes"] or 0)
                overload_penalty = min(
                    1.0,
                    max(0.0, (daily_planned_minutes - 480) / 480),
                )
                final_score = max(
                    0.0,
                    min(1.0, result["success_probability"] - 0.2 * overload_penalty),
                )
                candidates.append(
                    {
                        "candidate_start": current.isoformat(),
                        "candidate_end": end.isoformat(),
                        "predicted_success_probability": result["success_probability"],
                        "conflict_penalty": 0.0,
                        "overload_penalty": overload_penalty,
                        "preference_penalty": 0.0,
                        "final_score": final_score,
                        "rank": 0,
                        "feature_snapshot": context,
                        "reason_snapshot": {
                            "predicted_failure_reason": result["predicted_failure_reason"],
                            "strategy": "existing_success_model_with_hard_constraints",
                        },
                    }
                )
            current += timedelta(minutes=body.slot_interval_minutes)

        candidates.sort(key=lambda item: item["final_score"], reverse=True)
        for rank, candidate in enumerate(candidates, start=1):
            candidate["rank"] = rank
        return candidates[:10]

    @staticmethod
    def _revision_chain_ids(plan: dict[str, Any], rows: list[dict]) -> set[str]:
        by_parent: dict[str, list[str]] = {}
        for row in rows:
            parent = row.get("parent_plan_input_id")
            if parent:
                by_parent.setdefault(str(parent), []).append(str(row.get("id")))
        excluded = {str(plan.get("id"))}
        frontier = list(excluded)
        while frontier:
            parent = frontier.pop()
            for child in by_parent.get(parent, []):
                if child not in excluded:
                    excluded.add(child)
                    frontier.append(child)
        parent = plan.get("parent_plan_input_id")
        while parent:
            parent_id = str(parent)
            if parent_id in excluded:
                break
            excluded.add(parent_id)
            parent_row = next((row for row in rows if str(row.get("id")) == parent_id), None)
            parent = parent_row.get("parent_plan_input_id") if parent_row else None
        return excluded

    @staticmethod
    def _conflicts(
        start: datetime,
        end: datetime,
        schedule: list[dict],
        buffer_minutes: int,
    ) -> bool:
        buffer = timedelta(minutes=buffer_minutes)
        for row in schedule:
            row_start = _parse_datetime(row.get("planned_start"))
            row_end = row_start + timedelta(minutes=int(row.get("planned_duration_minutes", 0)))
            if start < row_end + buffer and end + buffer > row_start:
                return True
        return False

    @staticmethod
    def _schedule_context(
        candidate_start: datetime,
        plan: dict[str, Any],
        schedule: list[dict],
    ) -> dict[str, int | None]:
        timezone_name = str(plan.get("timezone_name") or "UTC")
        local_date = as_local(candidate_start, timezone_name).date()
        same_day: list[tuple[datetime, int]] = []
        for row in schedule:
            start = _parse_datetime(row.get("planned_start"))
            if as_local(start, timezone_name).date() == local_date:
                same_day.append((start, int(row.get("planned_duration_minutes", 0))))
        before = [item for item in same_day if item[0] < candidate_start]
        minutes_before = sum(duration for _start, duration in before)
        daily_minutes = sum(duration for _start, duration in same_day) + int(
            plan["planned_duration_minutes"]
        )
        minutes_since_previous: int | None = None
        if before:
            previous_start, previous_duration = max(before, key=lambda item: item[0])
            previous_end = previous_start + timedelta(minutes=previous_duration)
            minutes_since_previous = max(
                0, int((candidate_start - previous_end).total_seconds() // 60)
            )
        return {
            "tasks_before_count": len(before),
            "planned_minutes_before": minutes_before,
            "daily_planned_minutes": daily_minutes,
            "minutes_since_previous": minutes_since_previous,
        }
