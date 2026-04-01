"""
Evaluation: time-based or stratified split, metrics for Model 1 (AUC, accuracy, log-loss, calibration)
and Model 2 (macro F1, confusion matrix). Output metrics.json.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.calibration import calibration_curve
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    log_loss,
    roc_auc_score,
)
from sklearn.model_selection import train_test_split

from .data import (
    create_success_target,
    filter_failed_rows,
    filter_success_rows,
    get_reason_labels,
    load_and_clean,
    PLANNED_START_COL,
)
from .features import PlanTimeFeatureBuilder
from .model_failure import (
    load_failure_pipeline,
    predict_failure_proba_and_contributions,
)
from .model_success import load_success_pipeline, predict_from_pipeline


RANDOM_STATE = 42
VAL_FRAC = 0.2


def _time_split(df: pd.DataFrame, val_frac: float = VAL_FRAC) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split by time: earlier rows train, later rows validation."""
    if PLANNED_START_COL not in df.columns or df[PLANNED_START_COL].isna().all():
        # Fallback: stratified split by y_success
        train_idx, val_idx = train_test_split(
            df.index,
            test_size=val_frac,
            stratify=df["y_success"],
            random_state=RANDOM_STATE,
        )
        return df.loc[train_idx], df.loc[val_idx]
    df = df.sort_values(PLANNED_START_COL)
    n = len(df)
    cut = int(n * (1 - val_frac))
    return df.iloc[:cut], df.iloc[cut:]


def brier_score(y_true: np.ndarray, y_prob: np.ndarray) -> float:
    return float(np.mean((y_prob - y_true) ** 2))


def evaluate_success(
    df: pd.DataFrame,
    y_true: np.ndarray,
    pipeline: dict,
    feature_builder: PlanTimeFeatureBuilder,
) -> dict[str, Any]:
    """AUC, accuracy, log-loss, Brier score, and calibration curve data."""
    X = feature_builder.transform(df)
    p_pred, _ = predict_from_pipeline(pipeline, X, feature_builder=feature_builder)
    y_true = np.ravel(y_true)
    prob_pos = np.clip(p_pred, 1e-8, 1 - 1e-8)
    n_classes = len(np.unique(y_true))
    if n_classes < 2:
        return {"auc": None, "accuracy": float(accuracy_score(y_true, (p_pred >= 0.5).astype(int))), "log_loss": None, "brier_score": None, "calibration": None}
    auc = float(roc_auc_score(y_true, prob_pos))
    acc = float(accuracy_score(y_true, (p_pred >= 0.5).astype(int)))
    ll = float(log_loss(y_true, prob_pos))
    brier = brier_score(y_true, prob_pos)
    try:
        frac_pos, mean_pred = calibration_curve(y_true, prob_pos, n_bins=5)
        calibration = {"frac_pos": frac_pos.tolist(), "mean_pred": mean_pred.tolist()}
    except Exception:
        calibration = None
    return {
        "auc": auc,
        "accuracy": acc,
        "log_loss": ll,
        "brier_score": brier,
        "calibration": calibration,
    }


def evaluate_failure(
    df: pd.DataFrame,
    y_true_labels: pd.Series,
    pipeline: dict,
    feature_builder: PlanTimeFeatureBuilder,
) -> dict[str, Any]:
    """Macro F1 and confusion matrix. y_true_labels: string labels."""
    if pipeline is None or not y_true_labels.notna().all() or len(y_true_labels) == 0:
        return {"macro_f1": None, "confusion_matrix": None, "class_names": []}
    X = feature_builder.transform(df)
    le = pipeline["label_encoder"]
    try:
        y_enc = le.transform(y_true_labels.astype(str))
    except ValueError:
        return {"macro_f1": None, "confusion_matrix": None, "class_names": list(le.classes_)}
    proba, class_names, _ = predict_failure_proba_and_contributions(
        pipeline["model"], X, pipeline["feature_names"], le
    )
    y_pred = np.argmax(proba, axis=1)
    macro_f1 = float(f1_score(y_enc, y_pred, average="macro", zero_division=0))
    cm = confusion_matrix(y_enc, y_pred).tolist()
    return {"macro_f1": macro_f1, "confusion_matrix": cm, "class_names": class_names}


def run_evaluation(csv_path: str | Path, model_dir: str | Path) -> dict[str, Any]:
    """
    Load CSV, split by time (or stratified), load pipelines from model_dir, compute metrics.
    Saves and returns metrics dict.
    """
    model_dir = Path(model_dir)
    df = load_and_clean(csv_path)
    df = create_success_target(df)
    df_success = filter_success_rows(df)
    if len(df_success) == 0:
        return {"success": None, "failure": None, "note": "No completed/failed rows"}

    train_df, val_df = _time_split(df_success, val_frac=VAL_FRAC)
    success_path = model_dir / "success_model.joblib"
    failure_path = model_dir / "failure_model.joblib"

    if not success_path.exists():
        return {"success": None, "failure": None, "note": "success_model.joblib not found"}

    pipeline = load_success_pipeline(success_path)
    fb = pipeline["feature_builder"]
    # Persist feature builder state for eval (same as in pipeline)
    X_val = fb.transform(val_df)
    y_val = val_df["y_success"].astype(int).values
    success_metrics = evaluate_success(val_df, y_val, pipeline, fb)

    failure_metrics = None
    if failure_path.exists():
        fail_pipeline = load_failure_pipeline(failure_path)
        fail_df = filter_failed_rows(df)
        if len(fail_df) >= 2:
            fail_train, fail_val = _time_split(fail_df, val_frac=VAL_FRAC)
            if len(fail_val) > 0:
                reasons = get_reason_labels(fail_val)
                if len(reasons) > 0 and reasons.notna().all():
                    failure_metrics = evaluate_failure(
                        fail_val, reasons, fail_pipeline, fail_pipeline["feature_builder"]
                    )

    metrics = {"success": success_metrics, "failure": failure_metrics}
    out_path = model_dir / "metrics.json"
    with open(out_path, "w") as f:
        json.dump(metrics, f, indent=2)
    return metrics
