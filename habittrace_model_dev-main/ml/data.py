"""
Load CSV, parse, clean, and create targets for success/failure models.
- y_success: 1 = completed, 0 = failed. Skipped/canceled are DROPPED (documented).
- USER_ID: if column missing, add placeholder; personalization gated on its presence.
- Failure reasons are normalized into a smaller set of canonical labels.
"""
from __future__ import annotations

import re
from pathlib import Path

import numpy as np
import pandas as pd

# Expected CSV columns
USER_ID_COL = "user_id"
TASK_NAME_COL = "Task Name (Optional)"
CATEGORY_COL = "Category"
PLANNED_START_COL = "Planned Start Date & Time"
PLANNED_DURATION_COL = "Planned Duration (mins)"
IMPORTANCE_COL = "Importance (1-5)"
ENERGY_COL = "Energy Level (1-5)"
FOCUS_COL = "Focus Level (1-5)"
TOTAL_TASKS_TODAY_COL = "Total Tasks Today"
ACTUAL_START_COL = "Actual Start Time"
ACTUAL_END_COL = "Actual End Time"
INTERRUPTIONS_COL = "Interruptions (Count)"
STOPPED_EARLY_COL = "Stopped Early?"
TASK_STATUS_COL = "Task Status"
REASON_FAILURE_COL = "Reason for Failure (If failed)"

STATUS_COMPLETED = "completed"
STATUS_FAILED = "failed"
STATUS_SKIPPED = "skipped"
STATUS_CANCELED = "canceled"

# Canonical reason labels
CANONICAL_REASONS = {
    "start_delay": [
        "start_delay", "late_start", "started late", "procrastination", "procrastinated", "delay"
    ],
    "low_energy": [
        "low_energy", "tired", "fatigue", "sleepy", "exhausted", "too tired"
    ],
    "low_focus": [
        "low_focus", "distracted", "lost focus", "couldn't focus", "cant focus", "lack of focus"
    ],
    "interruptions": [
        "interruptions", "interruption", "interrupted", "disturbance", "disturbed"
    ],
    "time_underestimate": [
        "time_underestimate", "underestimated", "took longer", "not enough time", "too long"
    ],
    "schedule_conflict": [
        "schedule_conflict", "conflict", "overlap", "double booked", "another task"
    ],
    "unexpected_event": [
        "unexpected_event", "emergency", "urgent issue", "family issue", "sudden event"
    ],
}

MIN_REASON_COUNT = 5
RARE_REASON_FALLBACK = "other"
RARE_CATEGORY_FALLBACK = "other"
MIN_CATEGORY_COUNT = 3


def _normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    cols = {c: c.strip() for c in df.columns}
    for c in list(cols.keys()):
        if re.match(r"user_?id", c, re.I):
            cols[c] = USER_ID_COL
            break
    return df.rename(columns=cols)


def _ensure_user_id(df: pd.DataFrame) -> pd.DataFrame:
    if USER_ID_COL not in df.columns:
        df = df.copy()
        df[USER_ID_COL] = np.nan
    return df


def _normalize_status_value(x: object) -> str:
    s = str(x).strip().lower()
    if s in {"complete", "completed", "done", "success", "finished"}:
        return STATUS_COMPLETED
    if s in {"fail", "failed", "failure", "not completed"}:
        return STATUS_FAILED
    if s in {"skip", "skipped"}:
        return STATUS_SKIPPED
    if s in {"cancel", "canceled", "cancelled"}:
        return STATUS_CANCELED
    return s


def _normalize_category_series(s: pd.Series) -> pd.Series:
    out = s.fillna("unknown").astype(str).str.strip().str.lower()
    out = out.replace("", "unknown")
    return out


def _canonicalize_reason(text: object) -> str:
    s = str(text).strip().lower()
    if not s or s == "nan":
        return ""

    s_simple = re.sub(r"[^a-z0-9\s_]+", " ", s)
    s_simple = re.sub(r"\s+", " ", s_simple).strip()

    for canonical, variants in CANONICAL_REASONS.items():
        if s_simple == canonical:
            return canonical
        if s_simple in variants:
            return canonical
        for v in variants:
            if v in s_simple:
                return canonical

    return RARE_REASON_FALLBACK


def load_and_clean(csv_path: str | Path) -> pd.DataFrame:
    path = Path(csv_path)
    if not path.exists():
        raise FileNotFoundError(f"CSV not found: {path}")

    df = pd.read_csv(path)
    df = _normalize_columns(df)
    df = _ensure_user_id(df)

    if PLANNED_START_COL in df.columns:
        df[PLANNED_START_COL] = pd.to_datetime(df[PLANNED_START_COL], errors="coerce")
    for col in [ACTUAL_START_COL, ACTUAL_END_COL]:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

    numeric_cols = [
        PLANNED_DURATION_COL,
        IMPORTANCE_COL,
        ENERGY_COL,
        FOCUS_COL,
        TOTAL_TASKS_TODAY_COL,
        INTERRUPTIONS_COL,
    ]
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    if STOPPED_EARLY_COL in df.columns:
        df[STOPPED_EARLY_COL] = df[STOPPED_EARLY_COL].map(
            lambda x: str(x).strip().lower() in ("true", "1", "yes", "y") if pd.notna(x) else np.nan
        )

    if TASK_STATUS_COL in df.columns:
        df[TASK_STATUS_COL] = df[TASK_STATUS_COL].map(_normalize_status_value)

    if CATEGORY_COL in df.columns:
        df[CATEGORY_COL] = _normalize_category_series(df[CATEGORY_COL])

    if REASON_FAILURE_COL in df.columns:
        df[REASON_FAILURE_COL] = df[REASON_FAILURE_COL].map(_canonicalize_reason)

    return df


def create_success_target(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    if TASK_STATUS_COL not in out.columns:
        out["y_success"] = np.nan
        return out

    status = out[TASK_STATUS_COL]
    completed = status == STATUS_COMPLETED
    failed = status == STATUS_FAILED
    out["y_success"] = np.where(completed, 1, np.where(failed, 0, np.nan))
    return out


def filter_success_rows(df: pd.DataFrame) -> pd.DataFrame:
    if "y_success" not in df.columns:
        df = create_success_target(df)
    return df.loc[df["y_success"].notna()].copy()


def filter_failed_rows(df: pd.DataFrame) -> pd.DataFrame:
    df = filter_success_rows(df)
    failed = df[df["y_success"] == 0].copy()
    if REASON_FAILURE_COL in failed.columns:
        failed = failed[
            failed[REASON_FAILURE_COL].notna()
            & (failed[REASON_FAILURE_COL].astype(str).str.strip() != "")
        ].copy()

        counts = failed[REASON_FAILURE_COL].value_counts()
        rare = counts[counts < MIN_REASON_COUNT].index
        failed.loc[failed[REASON_FAILURE_COL].isin(rare), REASON_FAILURE_COL] = RARE_REASON_FALLBACK

    return failed


def get_reason_labels(df: pd.DataFrame) -> pd.Series:
    if REASON_FAILURE_COL not in df.columns:
        return pd.Series(dtype=object)
    return df[REASON_FAILURE_COL].astype(str).str.strip().str.lower()


def has_user_id(df: pd.DataFrame) -> bool:
    if USER_ID_COL not in df.columns:
        return False
    return df[USER_ID_COL].notna().any()


def collapse_rare_categories(df: pd.DataFrame, min_count: int = MIN_CATEGORY_COUNT) -> pd.DataFrame:
    if CATEGORY_COL not in df.columns:
        return df
    out = df.copy()
    counts = out[CATEGORY_COL].value_counts(dropna=False)
    rare = counts[counts < min_count].index
    out.loc[out[CATEGORY_COL].isin(rare), CATEGORY_COL] = RARE_CATEGORY_FALLBACK
    return out


def load_for_success_training(csv_path: str | Path) -> tuple[pd.DataFrame, pd.Series, bool]:
    df = load_and_clean(csv_path)
    df = create_success_target(df)
    df = filter_success_rows(df)
    df = collapse_rare_categories(df)
    y = df["y_success"].astype(int)
    has_uid = has_user_id(df)
    return df, y, has_uid


def load_for_failure_training(csv_path: str | Path) -> tuple[pd.DataFrame, pd.Series]:
    df = load_and_clean(csv_path)
    df = create_success_target(df)
    df = filter_failed_rows(df)
    df = collapse_rare_categories(df)
    reasons = get_reason_labels(df)
    return df, reasons