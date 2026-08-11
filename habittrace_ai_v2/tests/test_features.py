from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from habittrace_ai.contracts import assert_no_forbidden_features
from habittrace_ai.features import MODEL_FEATURE_COLUMNS, build_plan_features


def test_feature_builder_uses_explicit_leakage_safe_schema(plans: pd.DataFrame) -> None:
    contaminated = plans.copy()
    contaminated["completion_ratio"] = 1.0
    contaminated["actual_start"] = contaminated["planned_start"]

    features = build_plan_features(contaminated)

    assert list(features.columns) == list(MODEL_FEATURE_COLUMNS)
    assert "completion_ratio" not in features
    assert "actual_start" not in features
    assert_no_forbidden_features(features.columns)


def test_timezone_is_used_for_local_hour(plans: pd.DataFrame) -> None:
    sample = plans.iloc[[0]].copy()
    sample["planned_start"] = pd.Timestamp("2026-01-15T12:00:00Z")
    sample["timezone_name"] = "America/Denver"
    features = build_plan_features(sample)

    # Denver is UTC-7 in January, so the local hour is 05:00.
    expected_sin = np.sin(2 * np.pi * 5 / 24)
    expected_cos = np.cos(2 * np.pi * 5 / 24)
    assert features.iloc[0]["planned_local_hour_sin"] == pytest.approx(expected_sin)
    assert features.iloc[0]["planned_local_hour_cos"] == pytest.approx(expected_cos)


def test_naive_planned_start_is_rejected(plans: pd.DataFrame) -> None:
    sample = plans.iloc[[0]].copy()
    sample["planned_start"] = pd.Timestamp("2026-01-15T12:00:00")
    with pytest.raises(ValueError, match="timezone-aware"):
        build_plan_features(sample)


def test_deadline_and_readiness_features(plans: pd.DataFrame) -> None:
    sample = plans.iloc[[1]].copy()
    features = build_plan_features(sample).iloc[0]
    assert features["deadline_slack_minutes"] == pytest.approx(180.0)
    assert features["energy_gap"] == pytest.approx(
        float(sample.iloc[0]["required_energy"]) - float(sample.iloc[0]["current_energy"])
    )

