"""
Model 2: Failure-type predictor P(failure_type = k | failure).
Trained only on failed tasks with Reason for Failure. Multinomial Logistic Regression.
Outputs probability distribution over failure reasons + top-K contributions for predicted class.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import joblib
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import LabelEncoder

from .features import PlanTimeFeatureBuilder

RANDOM_STATE = 42
DEFAULT_TOP_K = 10


def train_failure_model(
    X: np.ndarray,
    y: np.ndarray,
    feature_names: list[str],
    C: float = 1.0,
    random_state: int = RANDOM_STATE,
) -> tuple[LogisticRegression, LabelEncoder, list[str]]:
    """
    Multinomial (softmax) logistic regression for failure reasons.
    y: string labels (Reason for Failure). Returns (model, label_encoder, feature_names).
    """
    le = LabelEncoder()
    y_enc = le.fit_transform(np.ravel(y).astype(str))
    n_classes = len(le.classes_)
    if n_classes < 2:
        raise ValueError("Need at least 2 failure reason classes to train Model 2.")

    # Multi-class: default solver="lbfgs" uses multinomial for >2 classes
    clf = LogisticRegression(
        C=C,
        random_state=random_state,
        max_iter=1000,
        solver="lbfgs",
    )
    clf.fit(X, y_enc)
    return clf, le, feature_names


def predict_failure_proba_and_contributions(
    model: LogisticRegression,
    X: np.ndarray,
    feature_names: list[str],
    label_encoder: LabelEncoder,
    top_k: int = DEFAULT_TOP_K,
) -> tuple[np.ndarray, list[str], list[list[dict[str, Any]]]]:
    """
    Returns (proba matrix, class_names), and per-sample list of contribution dicts
    for the *predicted* class (argmax).
    """
    proba = model.predict_proba(X)
    class_names = list(label_encoder.classes_)
    pred_class = np.argmax(proba, axis=1)
    contributions_list = []
    for i in range(X.shape[0]):
        k = pred_class[i]
        coef = model.coef_[k]
        contribs = coef * X[i]
        named = [{"feature": feature_names[j], "contribution": float(contribs[j]), "value": float(X[i, j])} for j in range(len(feature_names))]
        named.sort(key=lambda x: -abs(x["contribution"]))
        contributions_list.append(named[:top_k])
    return proba, class_names, contributions_list


def build_failure_pipeline(
    feature_builder: PlanTimeFeatureBuilder,
    model: LogisticRegression,
    label_encoder: LabelEncoder,
) -> dict:
    return {
        "feature_builder": feature_builder,
        "model": model,
        "label_encoder": label_encoder,
        "feature_names": feature_builder.get_feature_names(),
        "class_names": list(label_encoder.classes_),
    }


def save_failure_pipeline(pipeline: dict, path: str | Path) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(pipeline, path)


def load_failure_pipeline(path: str | Path) -> dict:
    return joblib.load(Path(path))
