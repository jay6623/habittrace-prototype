"""Independent conditional probabilities for user-confirmed failure reasons."""

from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from sklearn.dummy import DummyClassifier
from sklearn.pipeline import Pipeline

from habittrace_ai.contracts import FAILURE_REASON_CODES
from habittrace_ai.features import MODEL_FEATURE_COLUMNS, build_plan_features
from habittrace_ai.labels import FAILURE_REASON_LABEL_POLICY
from habittrace_ai.models.common import logistic_pipeline


class FailureReasonProbabilityModel:
    """One binary classifier per reason; outputs are conditional on failure."""

    model_type = "failure_reason_independent_logistic_regression"
    feature_columns = MODEL_FEATURE_COLUMNS
    reason_codes = FAILURE_REASON_CODES
    label_policy = FAILURE_REASON_LABEL_POLICY

    def __init__(self) -> None:
        self.pipelines: dict[str, Pipeline[Any]] = {}

    def fit(
        self,
        plans: pd.DataFrame,
        targets: pd.DataFrame,
    ) -> FailureReasonProbabilityModel:
        if len(plans) != len(targets):
            raise ValueError("plans and failure targets must have the same length")
        if plans.empty:
            raise ValueError("at least one confirmed failed outcome is required")
        if not plans.index.equals(targets.index):
            raise ValueError("plans and failure targets must have the same ordered index")
        if list(targets.columns) != list(FAILURE_REASON_CODES):
            raise ValueError("failure targets must contain all reason codes in contract order")
        try:
            numeric_targets = targets.to_numpy(dtype=float)
        except (TypeError, ValueError) as exc:
            raise ValueError("failure targets must contain only binary values") from exc
        if not np.all(np.isfinite(numeric_targets)) or not set(
            np.unique(numeric_targets)
        ).issubset({0.0, 1.0}):
            raise ValueError("failure targets must contain only binary values")
        features = build_plan_features(plans)
        self.pipelines = {}
        for reason in FAILURE_REASON_CODES:
            reason_index = FAILURE_REASON_CODES.index(reason)
            y = numeric_targets[:, reason_index].astype(int)
            unique = np.unique(y)
            if unique.size == 1:
                pipeline: Pipeline[Any] = Pipeline(
                    steps=[
                        (
                            "classifier",
                            DummyClassifier(strategy="constant", constant=int(unique[0])),
                        )
                    ]
                )
            else:
                pipeline = logistic_pipeline()
            pipeline.fit(features, y)
            self.pipelines[reason] = pipeline
        return self

    def is_fitted(self) -> bool:
        return set(self.pipelines) == set(FAILURE_REASON_CODES)

    @staticmethod
    def _positive_probability(pipeline: Pipeline[Any], features: pd.DataFrame) -> np.ndarray:
        classifier = pipeline.named_steps["classifier"]
        classes = np.asarray(classifier.classes_)
        positive = np.flatnonzero(classes == 1)
        if positive.size == 0:
            return np.zeros(len(features), dtype=float)
        probabilities = pipeline.predict_proba(features)
        return np.asarray(probabilities[:, int(positive[0])], dtype=float)

    def predict_reason_probabilities(self, plans: pd.DataFrame) -> pd.DataFrame:
        if not self.is_fitted():
            raise RuntimeError("model must be fitted before prediction")
        features = build_plan_features(plans)
        return pd.DataFrame(
            {
                reason: self._positive_probability(self.pipelines[reason], features)
                for reason in FAILURE_REASON_CODES
            },
            index=plans.index,
        )
