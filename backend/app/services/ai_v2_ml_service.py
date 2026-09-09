"""Runtime loader for AI V2 model artifacts."""

from __future__ import annotations

import logging
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from ..config import settings
from .ai_explanation import build_plan_explanation

logger = logging.getLogger(__name__)
UTC = timezone.utc

_AI_V2_ROOT = Path(settings.ai_v2_code_dir)
_AI_V2_SRC = _AI_V2_ROOT / "src"
if str(_AI_V2_SRC) not in sys.path:
    sys.path.insert(0, str(_AI_V2_SRC))

try:
    from habittrace_ai.artifacts import load_model_artifact  # type: ignore[import-untyped]

    _AI_V2_AVAILABLE = True
except ImportError as exc:  # pragma: no cover - environment-specific import guard
    logger.warning("AI V2 modules could not be imported: %s", exc)
    _AI_V2_AVAILABLE = False


class AIV2MLService:
    def __init__(self) -> None:
        self.success_model: Any | None = None
        self.failure_model: Any | None = None
        self.model_version = ""

    def load(self) -> None:
        if not _AI_V2_AVAILABLE:
            raise RuntimeError("AI V2 package is not available")
        success_path = Path(settings.ai_v2_artifacts_dir) / "success_model.joblib"
        failure_path = Path(settings.ai_v2_artifacts_dir) / "failure_reason_model.joblib"
        success_model, success_manifest = load_model_artifact(
            success_path,
        )
        if success_manifest["model_type"] not in {
            "success_logistic_regression",
            "success_validated_candidate",
        }:
            raise ValueError("Unsupported success model type")
        self.model_evidence = {
            "data_source": success_manifest.get("metrics", {}).get("data_source", "synthetic"),
            "production_ready": success_manifest.get("metrics", {}).get("production_ready", False),
        }
        failure_model, failure_manifest = load_model_artifact(
            failure_path,
            expected_model_type="failure_reason_independent_logistic_regression",
        )
        if success_manifest["model_version"] != failure_manifest["model_version"]:
            raise ValueError("AI V2 success and failure artifacts have different versions")
        self.success_model = success_model
        self.failure_model = failure_model
        self.model_version = str(success_manifest["model_version"])
        logger.info("AI V2 artifacts loaded: %s", self.model_version)

    @property
    def is_ready(self) -> bool:
        return self.success_model is not None and self.failure_model is not None

    def predict(self, plan: dict[str, Any]) -> dict[str, Any]:
        if not self.is_ready:
            raise RuntimeError("AI V2 models are not loaded")
        assert self.success_model is not None
        assert self.failure_model is not None
        frame = pd.DataFrame([plan])
        success_probability = float(self.success_model.predict_success_probability(frame)[0])
        failure_frame = self.failure_model.predict_reason_probabilities(frame).iloc[0]
        failure_probabilities = {
            str(reason): float(probability)
            for reason, probability in failure_frame.to_dict().items()
        }
        support = getattr(self.failure_model, "support", {})
        supported = {
            reason: probability
            for reason, probability in failure_probabilities.items()
            if not support or support.get(reason, {}).get("positive", 0) >= 10
        }
        predicted_failure_reason = max(supported, key=supported.get) if supported else None
        result = {
            "model_version": self.model_version,
            "success_probability": success_probability,
            "failure_reason_probabilities": failure_probabilities,
            "predicted_failure_reason": predicted_failure_reason,
            "predicted_at": datetime.now(UTC),
        }
        explanation = build_plan_explanation(plan, result)
        explanation["model_evidence"] = getattr(self, "model_evidence", {"production_ready": False})
        explanation["notice"] = (
            "Experimental planning guidance, not a validated personal success probability."
        )
        result["explanation"] = explanation
        result["recommended_actions"] = explanation["recommended_actions"]
        return result


_service = AIV2MLService()


def get_ai_v2_ml_service() -> AIV2MLService:
    return _service
