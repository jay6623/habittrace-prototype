"""Select on validation only; test outcomes never enter fitting or selection."""

from __future__ import annotations

import copy
from typing import Any

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression

from habittrace_ai.evaluation import evaluate_binary_probabilities
from habittrace_ai.features import build_plan_features
from habittrace_ai.models.success import SuccessProbabilityModel
from habittrace_ai.split import temporal_train_validation_test_split


class SelectedSuccessModel(SuccessProbabilityModel):
    model_type = "success_validated_candidate"

    def __init__(self) -> None:
        super().__init__()
        self.calibrator: Any = None
        self.selected_candidate = ""

    def predict_success_probability(self, plans: pd.DataFrame) -> np.ndarray:
        probability = super().predict_success_probability(plans)
        if self.calibrator is not None:
            logits = np.log(
                np.clip(probability, 1e-6, 1 - 1e-6) / np.clip(1 - probability, 1e-6, 1)
            )
            probability = self.calibrator.predict_proba(logits.reshape(-1, 1))[:, 1]
        return np.asarray(probability, dtype=float)


def select_success_model(
    train: pd.DataFrame, validation: pd.DataFrame
) -> tuple[SelectedSuccessModel, dict[str, Any]]:
    if len(train) < 100 or len(validation) < 30:
        raise ValueError(
            "Model comparison requires at least 100 training and 30 validation outcomes"
        )
    candidates: dict[str, SuccessProbabilityModel] = {}
    for regularization in (0.01, 0.1, 1.0):
        model = SuccessProbabilityModel()
        # Fit fresh preprocessing for every candidate; no validation statistics.
        model.fit(train, train["success_label"])
        assert model.pipeline is not None
        model.pipeline.set_params(classifier__C=regularization)
        model.pipeline.fit(build_plan_features(train), train["success_label"])
        candidates[f"logistic_C_{regularization}"] = model
    tree = copy.deepcopy(candidates["logistic_C_1.0"])
    assert tree.pipeline is not None
    tree.pipeline.set_params(preprocessing__categorical__one_hot__sparse_output=False)
    tree.pipeline.set_params(
        classifier=HistGradientBoostingClassifier(
            max_iter=100,
            max_leaf_nodes=7,
            min_samples_leaf=30,
            l2_regularization=5.0,
            learning_rate=0.05,
            early_stopping=False,
            random_state=42,
        )
    )
    tree.pipeline.fit(build_plan_features(train), train["success_label"])
    candidates["hist_gradient_boosting"] = tree

    # Sigmoid candidate calibrated on a later portion of training data, never
    # the selection validation set. Preserve label availability and lineage rules.
    inner = temporal_train_validation_test_split(
        train, train_fraction=0.7, validation_fraction=0.15
    )
    calibration = pd.concat([inner.validation, inner.test])
    if (
        len(inner.train) >= 60
        and len(calibration) >= 30
        and calibration.success_label.nunique() == 2
        and inner.train.success_label.nunique() == 2
    ):
        calibrated = SelectedSuccessModel()
        calibrated.fit(inner.train, inner.train.success_label)
        p = calibrated.predict_success_probability(calibration)
        logits = np.log(np.clip(p, 1e-6, 1 - 1e-6) / np.clip(1 - p, 1e-6, 1))
        calibrated.calibrator = LogisticRegression(C=1.0, random_state=42).fit(
            logits.reshape(-1, 1), calibration.success_label
        )
        candidates["sigmoid_logistic"] = calibrated

    scores = {
        name: evaluate_binary_probabilities(
            validation.success_label, model.predict_success_probability(validation)
        )
        for name, model in candidates.items()
    }
    best = min(scores, key=lambda name: (scores[name]["brier_score"], scores[name]["log_loss"]))
    selected = SelectedSuccessModel()
    selected.pipeline = candidates[best].pipeline
    selected.calibrator = getattr(candidates[best], "calibrator", None)
    selected.selected_candidate = best
    return selected, {
        "selection_metric": "validation_brier_then_log_loss",
        "selected": best,
        "candidates": scores,
    }
