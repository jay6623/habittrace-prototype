"""
Per-user calibration for Model 1: p_personal = sigmoid( logit(p_global) + b_user )
Optional: p_personal = sigmoid( a_user * logit(p_global) + b_user ).
Online update with regularization toward b->0, a->1. Activate after N>=30 or strong regularization when N small.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

MIN_TASKS_FOR_CALIBRATION = 30
REG_B = 0.1
REG_A = 0.1


def logit(p: float | np.ndarray) -> float | np.ndarray:
    p = np.clip(np.asarray(p, dtype=float), 1e-8, 1 - 1e-8)
    return np.log(p / (1 - p))


def sigmoid(x: float | np.ndarray) -> float | np.ndarray:
    return 1.0 / (1.0 + np.exp(-np.asarray(x, dtype=float)))


def predict_personalized(
    p_global: float,
    b_user: float,
    a_user: float | None = None,
) -> float:
    """p_personal = sigmoid( a_user * logit(p_global) + b_user ), or sigmoid(logit + b) if a_user is None."""
    L = logit(float(p_global))
    if a_user is not None:
        L = float(a_user) * L + float(b_user)
    else:
        L = L + float(b_user)
    return float(sigmoid(L))


def online_update_b(
    b_current: float,
    p_global: float,
    y_observed: int,
    n_user: int,
    learning_rate: float = 0.1,
    reg: float = REG_B,
) -> float:
    """
    One-step update for b_user. Gradient of log-loss for p_personal w.r.t. b, then regularize toward 0.
    """
    p_global = np.clip(float(p_global), 1e-8, 1 - 1e-8)
    p_pers = predict_personalized(p_global, b_current, None)
    # d/db log-loss: (p_pers - y)
    grad = (p_pers - float(y_observed))
    # Shrink step when n is small (stronger regularization)
    strength = 1.0 / (1.0 + reg * max(0, MIN_TASKS_FOR_CALIBRATION - n_user))
    b_new = b_current - learning_rate * (grad + reg * b_current * strength)
    return float(b_new)


def online_update_a_b(
    a_current: float,
    b_current: float,
    p_global: float,
    y_observed: int,
    n_user: int,
    lr: float = 0.05,
    reg_b: float = REG_B,
    reg_a: float = REG_A,
) -> tuple[float, float]:
    """
    One-step update for (a_user, b_user). Regularize b toward 0, a toward 1.
    """
    p_global = np.clip(float(p_global), 1e-8, 1 - 1e-8)
    L = logit(p_global)
    p_pers = sigmoid(a_current * L + b_current)
    y = float(y_observed)
    # Gradients of log-loss
    err = p_pers - y
    da = err * L * p_pers * (1 - p_pers)
    db = err * p_pers * (1 - p_pers)
    strength = 1.0 / (1.0 + max(0, MIN_TASKS_FOR_CALIBRATION - n_user) * 0.1)
    a_new = a_current - lr * (da + reg_a * (a_current - 1.0) * strength)
    b_new = b_current - lr * (db + reg_b * b_current * strength)
    return float(np.clip(a_new, 0.1, 10.0)), float(b_new)


def load_calib_params(path: str | Path) -> dict[str, Any]:
    path = Path(path)
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def save_calib_params(params: dict[str, Any], path: str | Path) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(params, f, indent=2)


def get_user_params(
    calib_params: dict[str, Any],
    user_id: str,
) -> tuple[float, float | None]:
    """Returns (b_user, a_user or None). Default b=0, a=None (identity)."""
    users = calib_params.get("users", {})
    u = users.get(user_id, {})
    b = u.get("b", 0.0)
    a = u.get("a")
    return float(b), float(a) if a is not None else None


def set_user_params(
    calib_params: dict[str, Any],
    user_id: str,
    b: float,
    n: int,
    a: float | None = None,
) -> dict[str, Any]:
    out = dict(calib_params)
    users = out.setdefault("users", {})
    users[user_id] = {"b": b, "n": n, **({"a": a} if a is not None else {})}
    return out


def is_personalization_active(n_user: int, min_tasks: int = MIN_TASKS_FOR_CALIBRATION) -> bool:
    """If N >= min_tasks, consider calibration 'active' (less regularization in updates)."""
    return n_user >= min_tasks
