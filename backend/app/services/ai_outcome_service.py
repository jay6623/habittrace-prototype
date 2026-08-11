"""Business rules for one immutable outcome per plan input."""
from __future__ import annotations

from uuid import UUID

from ..core.errors import ResourceConflictError, ResourceNotFoundError
from ..repositories.ai_outcome_repository import AIOutcomeRepository
from ..repositories.ai_plan_repository import AIPlanRepository
from ..schemas.ai_outcome import OutcomeCreate, outcome_to_insert


class AIOutcomeService:
    def __init__(
        self,
        plans: AIPlanRepository,
        outcomes: AIOutcomeRepository,
    ) -> None:
        self.plans = plans
        self.outcomes = outcomes

    def create(
        self, user_id: UUID, plan_input_id: UUID, body: OutcomeCreate
    ) -> dict:
        if self.plans.get_owned(plan_input_id, user_id) is None:
            raise ResourceNotFoundError("Plan not found.")
        if self.outcomes.get_by_plan(plan_input_id) is not None:
            raise ResourceConflictError("This plan already has an outcome.")
        return self.outcomes.create(
            outcome_to_insert(body, plan_input_id=plan_input_id)
        )
