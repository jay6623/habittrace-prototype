from __future__ import annotations

import pandas as pd
import pytest

from habittrace_ai.dataset import build_training_datasets
from habittrace_ai.labels import derive_success_labels


def test_success_definition_is_derived_exactly() -> None:
    outcomes = pd.DataFrame(
        {
            "outcome_status": ["completed", "completed", "partial", "abandoned"],
            "completion_ratio": [0.8, 0.79, 1.0, 1.0],
        }
    )
    assert derive_success_labels(outcomes).tolist() == [True, False, False, False]


def test_invalid_completion_ratio_is_rejected() -> None:
    outcomes = pd.DataFrame({"outcome_status": ["completed"], "completion_ratio": [float("nan")]})
    with pytest.raises(ValueError, match="completion_ratio"):
        derive_success_labels(outcomes)


def test_only_plans_with_outcomes_enter_success_training(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    datasets = build_training_datasets(plans, outcomes, failure_reasons)
    assert len(datasets.success_examples) == len(outcomes)
    assert plans.iloc[-1]["id"] not in set(datasets.success_examples["id"])
    assert "actual_start" not in datasets.success_examples.columns
    assert "completion_ratio" not in datasets.success_examples.columns


def test_only_confirmed_reasons_become_failure_targets(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    datasets = build_training_datasets(plans, outcomes, failure_reasons)
    assert datasets.failure_targets["unexpected_event"].sum() == 0
    assert datasets.failure_targets["schedule_overload"].eq(1).all()
    assert len(datasets.failure_examples) == len(datasets.failure_targets)
    assert datasets.failure_examples.index.equals(datasets.failure_targets.index)


def test_confirmed_unknown_reason_is_rejected(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    changed = failure_reasons.copy()
    changed.loc[changed.index[0], "reason_code"] = "model_invented_reason"
    with pytest.raises(ValueError, match="unknown confirmed reason_code"):
        build_training_datasets(plans, outcomes, changed)


def test_confirmed_reason_on_success_is_rejected(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    successful_outcome = outcomes.loc[
        (outcomes["outcome_status"] == "completed") & (outcomes["completion_ratio"] >= 0.8)
    ].iloc[0]
    invalid = pd.concat(
        [
            failure_reasons,
            pd.DataFrame(
                [
                    {
                        "outcome_id": successful_outcome["id"],
                        "reason_code": "other",
                        "is_primary": True,
                        "user_confirmed": True,
                        "created_at": successful_outcome["recorded_at"],
                    }
                ]
            ),
        ],
        ignore_index=True,
    )
    with pytest.raises(ValueError, match="successful outcomes"):
        build_training_datasets(plans, outcomes, invalid)
