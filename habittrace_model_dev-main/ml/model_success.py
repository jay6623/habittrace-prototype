"""
Model 1: Success probability predictor P(success).
Logistic Regression (L2), outputs p_global_success and top-K feature contributions.
Contributions: w_i * x_i in scaled feature space (explain in output that values are on scaled inputs).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression

from .features import PlanTimeFeatureBuilder


RANDOM_STATE = 42
DEFAULT_TOP_K = 10


def train_success_model(
    X: np.ndarray,
    y: np.ndarray,
    feature_names: list[str],
    C: float = 1.0,
    random_state: int = RANDOM_STATE,
) -> tuple[LogisticRegression, list[str]]:
    """
    Train logistic regression for binary success. Returns (fitted model, feature_names).
    """
    clf = LogisticRegression(
        C=C,
        random_state=random_state,
        max_iter=1000,
        solver="lbfgs",
    )
    clf.fit(X, y)
    return clf, feature_names


def predict_proba_and_contributions(
    model: LogisticRegression,
    X: np.ndarray,
    feature_names: list[str],
    top_k: int = DEFAULT_TOP_K,
) -> tuple[np.ndarray, list[list[dict[str, Any]]]]:
    """
    Predict P(success) and per-sample top-K positive/negative contributions.
    contribution_i = w_i * x_i (scaled space). Returns (proba[:, 1], list of contribution dicts per row).
    """
    if getattr(model, "classes_", None) is not None and len(model.classes_) == 2:
        coef = model.coef_[0]  # class 1 (success)
    else:
        coef = model.coef_.ravel()
    proba = model.predict_proba(X)
    if proba.shape[1] == 2:
        p_success = proba[:, 1]
    else:
        p_success = proba[:, 0]

    contributions_list = []
    for i in range(X.shape[0]):
        contribs = coef * X[i]
        named = [{"feature": feature_names[j], "contribution": float(contribs[j]), "value": float(X[i, j])} for j in range(len(feature_names))]
        named.sort(key=lambda x: -x["contribution"])
        top_pos = named[:top_k]
        named.sort(key=lambda x: x["contribution"])
        top_neg = named[:top_k]
        contributions_list.append({"positive": top_pos, "negative": top_neg})
    return p_success, contributions_list


def build_success_pipeline(feature_builder: PlanTimeFeatureBuilder, model: LogisticRegression) -> dict:
    """Bundle feature builder + model for save/load."""
    return {"feature_builder": feature_builder, "model": model, "feature_names": feature_builder.get_feature_names()}


def save_success_pipeline(pipeline: dict, path: str | Path) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Save model + feature builder state (builder has numpy in scaler -> joblib)
    joblib.dump(pipeline, path)


def load_success_pipeline(path: str | Path) -> dict:
    return joblib.load(Path(path))


def predict_from_pipeline(
    pipeline: dict,
    X_raw: np.ndarray,
    feature_builder: PlanTimeFeatureBuilder | None = None,
    top_k: int = DEFAULT_TOP_K,
) -> tuple[np.ndarray, list[list[dict]]]:
    """
    X_raw: already transformed by pipeline's feature_builder (e.g. feature_builder.transform(df)).
    If feature_builder is None, use pipeline['feature_builder'].
    """
    fb = feature_builder or pipeline["feature_builder"]
    model = pipeline["model"]
    names = pipeline.get("feature_names") or fb.get_feature_names()
    if X_raw.ndim == 1:
        X_raw = X_raw.reshape(1, -1)
    return predict_proba_and_contributions(model, X_raw, names, top_k=top_k)
