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
        if not np.all(np.isfinite(numeric_targets)) or not set(np.unique(numeric_targets)).issubset(
            {0.0, 1.0}
        ):
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

    def select_on_validation(
        self,
        train: pd.DataFrame,
        targets: pd.DataFrame,
        validation: pd.DataFrame,
        validation_targets: pd.DataFrame,
    ) -> FailureReasonProbabilityModel:
        from habittrace_ai.evaluation import evaluate_binary_probabilities

        features = build_plan_features(train)
        validation_features = build_plan_features(validation)
        self.support = {}
        self.selection = {}
        for reason in self.reason_codes:
            y = targets[reason]
            positives = int(y.sum())
            self.support[reason] = {"positive": positives, "negative": len(y) - positives}
            candidates = {"baseline": self.pipelines[reason]}
            # A Laplace-smoothed prior avoids unjustified 0/100% for rare labels.
            prior = (positives + 1) / (len(y) + 2)
            best_score = evaluate_binary_probabilities(
                validation_targets[reason], np.full(len(validation), prior)
            )["brier_score"]
            assert best_score is not None
            best = None
            name = "smoothed_prior"
            if min(positives, len(y) - positives) >= 10:
                regularized = logistic_pipeline()
                regularized.set_params(classifier__C=0.1)
                regularized.fit(features, y)
                candidates["regularized_logistic"] = regularized
                for candidate_name, pipeline in candidates.items():
                    score = evaluate_binary_probabilities(
                        validation_targets[reason],
                        self._positive_probability(pipeline, validation_features),
                    )["brier_score"]
                    assert score is not None
                    if score < best_score:
                        best_score, best, name = score, pipeline, candidate_name
            if best is None:
                # DummyClassifier with two weighted observations encodes a smoothed prior.
                best = Pipeline([("classifier", DummyClassifier(strategy="prior"))])
                best.fit(
                    features.iloc[:2],
                    np.array([0, 1]),
                    classifier__sample_weight=np.array([1 - prior, prior]),
                )
            self.pipelines[reason] = best
            self.selection[reason] = name
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
