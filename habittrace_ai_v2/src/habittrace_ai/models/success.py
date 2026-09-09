"""Interpretable success-probability baseline."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from sklearn.pipeline import Pipeline

from habittrace_ai.features import MODEL_FEATURE_COLUMNS, build_plan_features
from habittrace_ai.labels import SUCCESS_LABEL_POLICY
from habittrace_ai.models.common import logistic_pipeline


class SuccessProbabilityModel:
    """Logistic Regression trained only on plan-time fields."""

    model_type = "success_logistic_regression"
    feature_columns = MODEL_FEATURE_COLUMNS
    label_policy = SUCCESS_LABEL_POLICY

    def __init__(self) -> None:
        self.pipeline: Pipeline[Any] | None = None

    def fit(
        self,
        plans: pd.DataFrame,
        labels: pd.Series | np.ndarray,
    ) -> SuccessProbabilityModel:
        if isinstance(labels, pd.Series) and not plans.index.equals(labels.index):
            raise ValueError("plans and success labels must have the same ordered index")
        try:
            numeric_labels = np.asarray(labels, dtype=float)
        except (TypeError, ValueError) as exc:
            raise ValueError("success labels must be binary zero/one values") from exc
        if numeric_labels.ndim != 1:
            raise ValueError("success labels must be a one-dimensional binary vector")
        if not np.all(np.isfinite(numeric_labels)) or not set(np.unique(numeric_labels)).issubset(
            {0.0, 1.0}
        ):
            raise ValueError("success labels must be binary zero/one values")
        y = numeric_labels.astype(int)
        if len(plans) != len(y):
            raise ValueError("plans and labels must have the same length")
        if set(np.unique(y)) != {0, 1}:
            raise ValueError("success training data must contain both classes")
        self.pipeline = logistic_pipeline()
        self.pipeline.fit(build_plan_features(plans), y)
        return self

    def is_fitted(self) -> bool:
        return self.pipeline is not None

    def predict_success_probability(self, plans: pd.DataFrame) -> np.ndarray:
        if self.pipeline is None:
            raise RuntimeError("model must be fitted before prediction")
        probabilities = self.pipeline.predict_proba(build_plan_features(plans))
        classifier = self.pipeline.named_steps["classifier"]
        classes = np.asarray(classifier.classes_)
        positive_index = int(np.flatnonzero(classes == 1)[0])
        return np.asarray(probabilities[:, positive_index], dtype=float)
