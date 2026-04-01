"""
Feature engineering for plan-time inputs only.
Improved with:
- Category: one-hot
- Planned Start: hour sin/cos, after_9pm, late_night, weekday, weekend
- Planned Duration: raw, >45, >90
- Numeric: importance, energy, focus, total tasks
- Interaction features:
    * duration_x_energy
    * duration_x_focus
    * energy_x_focus
    * low_energy_long_task
    * low_focus_long_task
    * high_load_day
    * late_and_low_energy
"""
from __future__ import annotations

from typing import Any

import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler

from .data import (
    CATEGORY_COL,
    FOCUS_COL,
    ENERGY_COL,
    IMPORTANCE_COL,
    PLANNED_DURATION_COL,
    PLANNED_START_COL,
    TOTAL_TASKS_TODAY_COL,
)

DEFAULT_PLANNED_DURATION = 30
DEFAULT_IMPORTANCE = 3
DEFAULT_ENERGY = 3
DEFAULT_FOCUS = 3
DEFAULT_TOTAL_TASKS = 1


def _hour_sin_cos(dt: pd.Series) -> tuple[pd.Series, pd.Series]:
    hour = dt.dt.hour + dt.dt.minute / 60.0
    return np.sin(2 * np.pi * hour / 24), np.cos(2 * np.pi * hour / 24)


def _day_of_week(dt: pd.Series) -> pd.Series:
    return dt.dt.dayofweek


def _after_9pm(dt: pd.Series) -> pd.Series:
    hour = dt.dt.hour + dt.dt.minute / 60.0
    return (hour >= 21).astype(int)


def _late_night(dt: pd.Series) -> pd.Series:
    hour = dt.dt.hour + dt.dt.minute / 60.0
    return ((hour >= 23) | (hour < 5)).astype(int)


def _is_weekend(dt: pd.Series) -> pd.Series:
    return (dt.dt.dayofweek >= 5).astype(int)


def _duration_over_45(mins: pd.Series) -> pd.Series:
    return (mins > 45).astype(int)


def _duration_over_90(mins: pd.Series) -> pd.Series:
    return (mins > 90).astype(int)


class PlanTimeFeatureBuilder:
    def __init__(self):
        self.categories_: list[str] = []
        self.scaler_ = StandardScaler()
        self.median_planned_duration_ = DEFAULT_PLANNED_DURATION
        self.median_importance_ = DEFAULT_IMPORTANCE
        self.median_energy_ = DEFAULT_ENERGY
        self.median_focus_ = DEFAULT_FOCUS
        self.median_total_tasks_ = DEFAULT_TOTAL_TASKS
        self.feature_names_out_: list[str] = []

    def fit(self, df: pd.DataFrame) -> "PlanTimeFeatureBuilder":
        if CATEGORY_COL in df.columns:
            cat_vals = df[CATEGORY_COL].dropna().astype(str).str.strip().str.lower()
            self.categories_ = sorted(cat_vals.unique().tolist()) or ["unknown"]
        else:
            self.categories_ = ["unknown"]

        if PLANNED_DURATION_COL in df.columns:
            median = df[PLANNED_DURATION_COL].median()
            self.median_planned_duration_ = float(median) if pd.notna(median) else DEFAULT_PLANNED_DURATION

        if IMPORTANCE_COL in df.columns:
            median = df[IMPORTANCE_COL].median()
            self.median_importance_ = float(median) if pd.notna(median) else DEFAULT_IMPORTANCE

        if ENERGY_COL in df.columns:
            median = df[ENERGY_COL].median()
            self.median_energy_ = float(median) if pd.notna(median) else DEFAULT_ENERGY

        if FOCUS_COL in df.columns:
            median = df[FOCUS_COL].median()
            self.median_focus_ = float(median) if pd.notna(median) else DEFAULT_FOCUS

        if TOTAL_TASKS_TODAY_COL in df.columns:
            median = df[TOTAL_TASKS_TODAY_COL].median()
            self.median_total_tasks_ = float(median) if pd.notna(median) else DEFAULT_TOTAL_TASKS

        X = self._build_raw(df)
        self.scaler_.fit(X)
        self.feature_names_out_ = list(self._get_feature_names())
        return self

    def _get_feature_names(self) -> list[str]:
        names = []
        for c in self.categories_:
            names.append(f"cat_{c}")

        names.extend([
            "hour_sin",
            "hour_cos",
            "after_9pm",
            "late_night",
            "day_of_week",
            "is_weekend",
        ])

        names.extend([
            "planned_duration_mins",
            "duration_over_45",
            "duration_over_90",
        ])

        names.extend([
            IMPORTANCE_COL,
            ENERGY_COL,
            FOCUS_COL,
            TOTAL_TASKS_TODAY_COL,
        ])

        names.extend([
            "duration_x_energy",
            "duration_x_focus",
            "energy_x_focus",
            "low_energy_long_task",
            "low_focus_long_task",
            "high_load_day",
            "late_and_low_energy",
            "important_but_low_energy",
            "important_but_low_focus",
        ])
        return names

    def _build_raw(self, df: pd.DataFrame) -> np.ndarray:
        rows = []
        n = len(df)

        cat_col = (
            df[CATEGORY_COL]
            if CATEGORY_COL in df.columns
            else pd.Series(["unknown"] * n, index=df.index)
        )
        cat_col = cat_col.fillna("unknown").astype(str).str.strip().str.lower()

        for c in self.categories_:
            rows.append((cat_col == c).astype(float).values)

        dt = (
            df[PLANNED_START_COL]
            if PLANNED_START_COL in df.columns
            else pd.Series(pd.NaT, index=df.index)
        )
        dt = pd.to_datetime(dt, errors="coerce")
        fallback_time = pd.Timestamp("2025-01-01 12:00:00")
        dt = dt.fillna(fallback_time)

        h_sin, h_cos = _hour_sin_cos(dt)
        after_9pm = _after_9pm(dt)
        late_night = _late_night(dt)
        day_of_week = _day_of_week(dt).astype(float)
        is_weekend = _is_weekend(dt)

        rows.append(h_sin.values)
        rows.append(h_cos.values)
        rows.append(after_9pm.values)
        rows.append(late_night.values)
        rows.append(day_of_week.values)
        rows.append(is_weekend.values)

        dur = (
            df[PLANNED_DURATION_COL]
            if PLANNED_DURATION_COL in df.columns
            else pd.Series(self.median_planned_duration_, index=df.index)
        )
        dur = pd.to_numeric(dur, errors="coerce").fillna(self.median_planned_duration_)

        imp = (
            df[IMPORTANCE_COL]
            if IMPORTANCE_COL in df.columns
            else pd.Series(self.median_importance_, index=df.index)
        )
        imp = pd.to_numeric(imp, errors="coerce").fillna(self.median_importance_)

        en = (
            df[ENERGY_COL]
            if ENERGY_COL in df.columns
            else pd.Series(self.median_energy_, index=df.index)
        )
        en = pd.to_numeric(en, errors="coerce").fillna(self.median_energy_)

        fo = (
            df[FOCUS_COL]
            if FOCUS_COL in df.columns
            else pd.Series(self.median_focus_, index=df.index)
        )
        fo = pd.to_numeric(fo, errors="coerce").fillna(self.median_focus_)

        tot = (
            df[TOTAL_TASKS_TODAY_COL]
            if TOTAL_TASKS_TODAY_COL in df.columns
            else pd.Series(self.median_total_tasks_, index=df.index)
        )
        tot = pd.to_numeric(tot, errors="coerce").fillna(self.median_total_tasks_)

        duration_over_45 = _duration_over_45(dur)
        duration_over_90 = _duration_over_90(dur)

        rows.append(dur.values)
        rows.append(duration_over_45.values)
        rows.append(duration_over_90.values)

        rows.append(imp.values)
        rows.append(en.values)
        rows.append(fo.values)
        rows.append(tot.values)

        duration_x_energy = dur * en
        duration_x_focus = dur * fo
        energy_x_focus = en * fo
        low_energy_long_task = ((en <= 2) & (dur > 45)).astype(float)
        low_focus_long_task = ((fo <= 2) & (dur > 45)).astype(float)
        high_load_day = (tot >= 5).astype(float)
        late_and_low_energy = ((after_9pm == 1) & (en <= 2)).astype(float)
        important_but_low_energy = ((imp >= 4) & (en <= 2)).astype(float)
        important_but_low_focus = ((imp >= 4) & (fo <= 2)).astype(float)

        rows.append(duration_x_energy.values)
        rows.append(duration_x_focus.values)
        rows.append(energy_x_focus.values)
        rows.append(low_energy_long_task.values)
        rows.append(low_focus_long_task.values)
        rows.append(high_load_day.values)
        rows.append(late_and_low_energy.values)
        rows.append(important_but_low_energy.values)
        rows.append(important_but_low_focus.values)

        return np.column_stack(rows).astype(float)

    def transform(self, df: pd.DataFrame) -> np.ndarray:
        X = self._build_raw(df)
        return self.scaler_.transform(X)

    def get_feature_names(self) -> list[str]:
        return list(self.feature_names_out_) if self.feature_names_out_ else self._get_feature_names()

    def to_dict(self) -> dict[str, Any]:
        return {
            "categories": self.categories_,
            "median_planned_duration": self.median_planned_duration_,
            "median_importance": self.median_importance_,
            "median_energy": self.median_energy_,
            "median_focus": self.median_focus_,
            "median_total_tasks": self.median_total_tasks_,
            "scaler_mean": self.scaler_.mean_.tolist()
            if hasattr(self.scaler_, "mean_") and self.scaler_.mean_ is not None else [],
            "scaler_scale": self.scaler_.scale_.tolist()
            if hasattr(self.scaler_, "scale_") and self.scaler_.scale_ is not None else [],
            "feature_names": self.get_feature_names(),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "PlanTimeFeatureBuilder":
        self = cls()
        self.categories_ = d.get("categories", ["unknown"])
        self.median_planned_duration_ = d.get("median_planned_duration", DEFAULT_PLANNED_DURATION)
        self.median_importance_ = d.get("median_importance", DEFAULT_IMPORTANCE)
        self.median_energy_ = d.get("median_energy", DEFAULT_ENERGY)
        self.median_focus_ = d.get("median_focus", DEFAULT_FOCUS)
        self.median_total_tasks_ = d.get("median_total_tasks", DEFAULT_TOTAL_TASKS)
        self.feature_names_out_ = d.get("feature_names", [])

        mean = np.array(d.get("scaler_mean", []), dtype=float)
        scale = np.array(d.get("scaler_scale", []), dtype=float)
        if len(mean) and len(scale):
            self.scaler_.mean_ = mean
            self.scaler_.scale_ = scale
            self.scaler_.var_ = scale ** 2
            self.scaler_.n_features_in_ = len(mean)
        return self