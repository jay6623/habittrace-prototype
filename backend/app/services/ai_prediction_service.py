"""Persisted AI V2 inference for owned plan snapshots."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from ..config import settings
from ..core.errors import ResourceNotFoundError
from ..repositories.ai_plan_repository import AIPlanRepository
from ..repositories.ai_prediction_repository import AIPredictionRepository
from .ai_v2_ml_service import AIV2MLService

UTC = timezone.utc


class AIPredictionService:
    def __init__(
        self,
        plans: AIPlanRepository,
        predictions: AIPredictionRepository,
        model_service: AIV2MLService,
    ) -> None:
        self.plans = plans
        self.predictions = predictions
        self.model_service = model_service

    def predict_for_plan(self, user_id: UUID, plan_input_id: UUID) -> dict:
        plan = self.plans.get_owned(plan_input_id, user_id)
        if plan is None:
            raise ResourceNotFoundError("Plan not found.")
        if not self.model_service.is_ready:
            raise RuntimeError("AI V2 model artifacts are not loaded")

        result = self.model_service.predict(plan)
        version = self.model_service.model_version
        success_version = self._ensure_model_version("success", version)
        failure_version = self._ensure_model_version("failure_reason", version)
        predicted_at = datetime.now(UTC).isoformat()
        success = self.predictions.create_success_prediction(
            {
                "plan_input_id": str(plan_input_id),
                "model_version_id": success_version["id"],
                "success_probability": result["success_probability"],
                "feature_snapshot": {"feature_schema_version": "plan-features-v1"},
                "explanation_snapshot": result["explanation"],
                "predicted_at": predicted_at,
            }
        )
        failure = self.predictions.create_failure_prediction(
            {
                "success_prediction_id": success["id"],
                "model_version_id": failure_version["id"],
                "reason_probabilities": result["failure_reason_probabilities"],
                "explanation_snapshot": {
                    "predicted_failure_reason": result["predicted_failure_reason"],
                    **result["explanation"],
                },
                "predicted_at": predicted_at,
            }
        )
        return {
            **result,
            "success_prediction_id": success["id"],
            "failure_prediction_id": failure["id"],
            "model_version_ids": {
                "success": success_version["id"],
                "failure_reason": failure_version["id"],
            },
        }

    def latest_for_plan(self, user_id: UUID, plan_input_id: UUID) -> dict | None:
        plan = self.plans.get_owned(plan_input_id, user_id)
        if plan is None:
            raise ResourceNotFoundError("Plan not found.")

        success = self.predictions.get_latest_success_prediction(str(plan_input_id))
        if success is None:
            return None

        failure = self.predictions.get_latest_failure_prediction(str(success["id"]))
        failure_snapshot = (failure or {}).get("explanation_snapshot") or {}
        explanation = {
            key: value
            for key, value in failure_snapshot.items()
            if key in {"source", "factors", "recommended_actions"}
        }
        if not explanation:
            explanation = (success.get("explanation_snapshot") or {})
        success_model = self.predictions.get_model_version_by_id(
            str(success["model_version_id"])
        )
        failure_model = (
            self.predictions.get_model_version_by_id(str(failure["model_version_id"]))
            if failure
            else None
        )
        return {
            "model_version": (success_model or {}).get("version"),
            "success_probability": success["success_probability"],
            "failure_reason_probabilities": (failure or {}).get(
                "reason_probabilities", {}
            ),
            "predicted_failure_reason": failure_snapshot.get(
                "predicted_failure_reason"
            ),
            "explanation": explanation,
            "recommended_actions": explanation.get("recommended_actions", []),
            "success_prediction_id": success["id"],
            "failure_prediction_id": (failure or {}).get("id"),
            "model_version_ids": {
                "success": success["model_version_id"],
                "failure_reason": (
                    failure_model or {}
                ).get("id"),
            },
        }

    def ensure_model_version(self, model_type: str, version: str) -> dict:
        """Return the registry row used by another persisted AI prediction."""
        return self._ensure_model_version(model_type, version)

    def _ensure_model_version(self, model_type: str, version: str) -> dict:
        existing = self.predictions.get_model_version(model_type, version)
        if existing is not None:
            return existing
        manifest_name = (
            "success_model.joblib.manifest.json"
            if model_type == "success"
            else "failure_reason_model.joblib.manifest.json"
        )
        return self.predictions.create_model_version(
            {
                "model_type": model_type,
                "model_name": (
                    "success_logistic_regression"
                    if model_type == "success"
                    else "failure_reason_independent_logistic_regression"
                ),
                "version": version,
                "status": "staging",
                "artifact_uri": str(Path(settings.ai_v2_artifacts_dir) / manifest_name),
                "feature_schema_version": "plan-features-v1",
                "label_policy": {},
                "metrics": {},
                "trained_at": None,
            }
        )
