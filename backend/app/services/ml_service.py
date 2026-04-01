"""
ML inference service — loads the trained success + failure pipelines once at startup
and exposes a single predict() method used by the /predict route.

The existing ML code lives in habittrace_model_dev-main/ml/. We add that directory
to sys.path so we can import from ml.* without copying any source files.
"""
from __future__ import annotations

import logging
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

from ..config import settings

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# sys.path injection — done once at import time
# ---------------------------------------------------------------------------
_ml_code_dir = Path(settings.ml_code_dir)
if str(_ml_code_dir) not in sys.path:
    sys.path.insert(0, str(_ml_code_dir))

# These imports resolve only after the path is injected above
try:
    from ml.model_success import (
        predict_proba_and_contributions,
        load_success_pipeline,
    )
    from ml.model_failure import (
        predict_failure_proba_and_contributions,
        load_failure_pipeline,
    )
    from ml.personalize import (
        predict_personalized,
        get_user_params,
        load_calib_params,
    )
    from ml.data import (
        CATEGORY_COL,
        PLANNED_START_COL,
        PLANNED_DURATION_COL,
        IMPORTANCE_COL,
        ENERGY_COL,
        FOCUS_COL,
        TOTAL_TASKS_TODAY_COL,
    )
    _ML_AVAILABLE = True
except ImportError as e:
    logger.warning(f"ML modules could not be imported: {e}. Predictions will be unavailable.")
    _ML_AVAILABLE = False


# ---------------------------------------------------------------------------
# Time string parsing helpers
# ---------------------------------------------------------------------------
_TIME_FORMATS = [
    "%I:%M %p",    # "2:00 PM"
    "%I:%M%p",     # "2:00PM"
    "%H:%M",       # "14:00"
    "%H:%M:%S",    # "14:00:00"
]


def _parse_time_string(time_str: str) -> Optional[datetime]:
    """Parse a time string into a datetime (date part = today)."""
    time_str = time_str.strip()
    today = date.today()
    for fmt in _TIME_FORMATS:
        try:
            t = datetime.strptime(time_str, fmt)
            return datetime.combine(today, t.time())
        except ValueError:
            continue
    return None


def _build_dataframe(
    task_category: str,
    planned_start_time: str,
    planned_date: Optional[str],
    planned_duration_min: int,
    importance: int,
    energy_level: int,
    focus_level: int,
    total_tasks_today: int,
) -> "pd.DataFrame":
    """Build the 1-row DataFrame that the feature builder expects."""
    # Resolve the planned date
    target_date = date.today()
    if planned_date:
        try:
            target_date = date.fromisoformat(planned_date)
        except ValueError:
            pass

    # Parse time string and combine with date
    dt: Optional[datetime] = None
    time_str = planned_start_time.strip()
    for fmt in _TIME_FORMATS:
        try:
            t = datetime.strptime(time_str, fmt)
            dt = datetime.combine(target_date, t.time())
            break
        except ValueError:
            continue

    if dt is None:
        # Fallback: noon on the target date
        dt = datetime.combine(target_date, datetime.strptime("12:00", "%H:%M").time())

    row = {
        CATEGORY_COL: task_category.lower().strip(),
        PLANNED_START_COL: dt,
        PLANNED_DURATION_COL: float(planned_duration_min),
        IMPORTANCE_COL: float(importance),
        ENERGY_COL: float(energy_level),
        FOCUS_COL: float(focus_level),
        TOTAL_TASKS_TODAY_COL: float(total_tasks_today),
    }
    return pd.DataFrame([row])


# ---------------------------------------------------------------------------
# ML Service singleton
# ---------------------------------------------------------------------------

class MLService:
    def __init__(self) -> None:
        self._success_pipeline: Optional[dict] = None
        self._failure_pipeline: Optional[dict] = None
        self._calib_params: dict = {}
        self._loaded = False

    def load(self) -> None:
        if not _ML_AVAILABLE:
            logger.error("ML modules are not available — cannot load models.")
            return

        artifacts_dir = Path(settings.model_artifacts_dir)
        success_path = artifacts_dir / "success_model.joblib"
        failure_path = artifacts_dir / "failure_model.joblib"
        calib_path = artifacts_dir / "calib_params.json"

        if not success_path.exists():
            logger.error(f"Success model not found at {success_path}")
            return
        if not failure_path.exists():
            logger.error(f"Failure model not found at {failure_path}")
            return

        logger.info("Loading ML models from %s ...", artifacts_dir)
        self._success_pipeline = load_success_pipeline(success_path)
        self._failure_pipeline = load_failure_pipeline(failure_path)
        self._calib_params = load_calib_params(calib_path) if calib_path.exists() else {}
        self._loaded = True
        logger.info("ML models loaded successfully.")

    @property
    def is_ready(self) -> bool:
        return self._loaded and _ML_AVAILABLE

    def predict(
        self,
        task_category: str,
        planned_start_time: str,
        planned_date: Optional[str],
        planned_duration_min: int,
        importance: int,
        energy_level: int,
        focus_level: int,
        total_tasks_today: int,
        user_id: Optional[str] = None,
    ) -> dict:
        if not self.is_ready:
            raise RuntimeError("ML models are not loaded. Call ml_service.load() first.")

        df = _build_dataframe(
            task_category, planned_start_time, planned_date,
            planned_duration_min, importance, energy_level, focus_level, total_tasks_today,
        )

        # ── Success model ───────────────────────────────────────────────
        success_fb = self._success_pipeline["feature_builder"]
        X_success = success_fb.transform(df)
        feature_names = (
            self._success_pipeline.get("feature_names")
            or success_fb.get_feature_names()
        )

        p_success_arr, contributions_list = predict_proba_and_contributions(
            self._success_pipeline["model"], X_success, feature_names, top_k=5
        )
        p_success = float(p_success_arr[0])

        # ── Per-user calibration ────────────────────────────────────────
        personalized = False
        if user_id and self._calib_params:
            b_user, a_user = get_user_params(self._calib_params, user_id)
            if b_user != 0.0 or a_user is not None:
                p_success = predict_personalized(p_success, b_user, a_user)
                personalized = True

        # ── Failure model ───────────────────────────────────────────────
        failure_fb = self._failure_pipeline["feature_builder"]
        X_failure = failure_fb.transform(df)
        failure_feature_names = (
            self._failure_pipeline.get("feature_names")
            or failure_fb.get_feature_names()
        )

        failure_proba, class_names, _ = predict_failure_proba_and_contributions(
            self._failure_pipeline["model"],
            X_failure,
            failure_feature_names,
            self._failure_pipeline["label_encoder"],
            top_k=5,
        )

        failure_proba_row = failure_proba[0]
        predicted_failure_idx = int(np.argmax(failure_proba_row))
        predicted_failure_reason = class_names[predicted_failure_idx]

        failure_probabilities = {
            class_names[i]: round(float(failure_proba_row[i]), 4)
            for i in range(len(class_names))
        }

        # ── Feature contributions (from success model) ──────────────────
        contribs = contributions_list[0]
        top_positive = [
            {"feature": c["feature"], "contribution": round(c["contribution"], 4), "value": round(c["value"], 4)}
            for c in contribs["positive"][:5]
        ]
        top_negative = [
            {"feature": c["feature"], "contribution": round(c["contribution"], 4), "value": round(c["value"], 4)}
            for c in contribs["negative"][:5]
        ]

        return {
            "success_probability": round(p_success, 4),
            "personalized": personalized,
            "predicted_failure_reason": predicted_failure_reason,
            "failure_probabilities": failure_probabilities,
            "top_positive_factors": top_positive,
            "top_negative_factors": top_negative,
        }


# Module-level singleton
_ml_service: Optional[MLService] = None


def get_ml_service() -> MLService:
    global _ml_service
    if _ml_service is None:
        _ml_service = MLService()
    return _ml_service
