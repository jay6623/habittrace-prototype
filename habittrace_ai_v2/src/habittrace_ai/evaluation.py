"""Probability-focused metrics for offline model comparison."""

from __future__ import annotations

from typing import TypeAlias

import numpy as np
import pandas as pd
from sklearn.metrics import (
    average_precision_score,
    brier_score_loss,
    log_loss,
    roc_auc_score,
)

MetricValue: TypeAlias = float | None


def evaluate_binary_probabilities(
    truth: pd.Series | np.ndarray,
    probabilities: pd.Series | np.ndarray,
) -> dict[str, MetricValue]:
    """Evaluate calibration and ranking without thresholding probabilities."""

    try:
        numeric_truth = np.asarray(truth, dtype=float)
        y_probability = np.asarray(probabilities, dtype=float)
    except (TypeError, ValueError) as exc:
        raise ValueError("truth and probabilities must be numeric") from exc
    y_true = numeric_truth.astype(int)
    if y_true.shape[0] != y_probability.shape[0]:
        raise ValueError("truth and probabilities must have the same length")
    if not np.all(np.isfinite(numeric_truth)) or not set(np.unique(numeric_truth)).issubset(
        {0.0, 1.0}
    ):
        raise ValueError("truth must contain only binary zero/one labels")
    if not np.all(np.isfinite(y_probability)):
        raise ValueError("probabilities must be finite")
    if np.any((y_probability < 0.0) | (y_probability > 1.0)):
        raise ValueError("probabilities must be between zero and one")

    has_two_classes = np.unique(y_true).size == 2
    return {
        "roc_auc": float(roc_auc_score(y_true, y_probability)) if has_two_classes else None,
        "pr_auc": (
            float(average_precision_score(y_true, y_probability)) if has_two_classes else None
        ),
        "log_loss": float(log_loss(y_true, y_probability, labels=[0, 1])),
        "brier_score": float(brier_score_loss(y_true, y_probability)),
    }


def evaluate_failure_probabilities(
    truth: pd.DataFrame,
    probabilities: pd.DataFrame,
) -> dict[str, dict[str, MetricValue]]:
    """Evaluate each conditional failure-reason probability independently."""

    if list(truth.columns) != list(probabilities.columns):
        raise ValueError("truth and probability reason columns must match in order")
    if not truth.index.equals(probabilities.index):
        raise ValueError("truth and probability rows must have the same ordered index")
    return {
        reason: evaluate_binary_probabilities(truth[reason], probabilities[reason])
        for reason in truth.columns
    }
