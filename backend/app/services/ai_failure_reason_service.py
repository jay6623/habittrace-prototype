"""Business rules for user-confirmed failure reason assignments."""

from __future__ import annotations

from uuid import UUID

from ..core.errors import (
    DomainValidationError,
    ResourceConflictError,
    ResourceNotFoundError,
)
from ..repositories.ai_failure_reason_repository import AIFailureReasonRepository
from ..repositories.ai_outcome_repository import AIOutcomeRepository
from ..repositories.ai_plan_repository import AIPlanRepository
from ..schemas.ai_failure_reason import FailureReasonCreate
from ..schemas.ai_outcome import is_successful_outcome


class AIFailureReasonService:
    def __init__(
        self,
        plans: AIPlanRepository,
        outcomes: AIOutcomeRepository,
        reasons: AIFailureReasonRepository,
    ) -> None:
        self.plans = plans
        self.outcomes = outcomes
        self.reasons = reasons

    def list_active(self) -> list[dict]:
        return self.reasons.list_active_definitions()

    def create_for_outcome(
        self, user_id: UUID, outcome_id: UUID, body: FailureReasonCreate
    ) -> dict:
        outcome = self.outcomes.get_by_id(outcome_id)
        if outcome is None:
            raise ResourceNotFoundError("Outcome not found.")

        try:
            plan_input_id = UUID(str(outcome["plan_input_id"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise ResourceNotFoundError("Outcome not found.") from exc
        if self.plans.get_owned(plan_input_id, user_id) is None:
            # Return the same response for missing and non-owned resources.
            raise ResourceNotFoundError("Outcome not found.")
        if is_successful_outcome(outcome):
            raise DomainValidationError(
                "Failure reasons cannot be recorded for a successful outcome."
            )
        if self.reasons.list_for_outcome(outcome_id):
            raise ResourceConflictError(
                "Failure reasons have already been recorded for this outcome."
            )

        requested = [body.primary_reason_code, *body.secondary_reason_codes]
        active = self.reasons.find_active_codes(requested)
        missing = sorted(set(requested) - active)
        if missing:
            raise DomainValidationError(
                "Unknown or inactive failure reason code: " + ", ".join(missing)
            )

        rows = [
            {
                "outcome_id": str(outcome_id),
                "reason_code": body.primary_reason_code,
                "is_primary": True,
                "user_confirmed": True,
            },
            *[
                {
                    "outcome_id": str(outcome_id),
                    "reason_code": code,
                    "is_primary": False,
                    "user_confirmed": True,
                }
                for code in body.secondary_reason_codes
            ],
        ]
        self.reasons.create_many(rows)
        return {
            "outcome_id": outcome_id,
            "primary_reason_code": body.primary_reason_code,
            "secondary_reason_codes": body.secondary_reason_codes,
            "user_confirmed": True,
        }
