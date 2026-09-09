from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from habittrace_ai.artifacts import load_model_artifact, save_model_artifact
from habittrace_ai.dataset import build_training_datasets
from habittrace_ai.evaluation import calibration_bins, paired_brier_interval
from habittrace_ai.models.failure_reason import FailureReasonProbabilityModel
from habittrace_ai.models.selection import select_success_model
from habittrace_ai.split import temporal_train_validation_test_split


def test_validation_selection_and_artifact_roundtrip(tmp_path):
    root = Path(__file__).parents[1] / "fixtures"
    data = build_training_datasets(
        pd.read_csv(root / "synthetic_plans.csv"),
        pd.read_csv(root / "synthetic_outcomes.csv"),
        pd.read_csv(root / "synthetic_failure_reasons.csv"),
    )
    split = temporal_train_validation_test_split(data.success_examples)
    model, report = select_success_model(split.train, split.validation)
    scores = report["candidates"]
    assert report["selected"] == min(
        scores, key=lambda k: (scores[k]["brier_score"], scores[k]["log_loss"])
    )
    prediction = model.predict_success_probability(split.test)
    assert np.isfinite(prediction).all()
    path = tmp_path / "model.joblib"
    save_model_artifact(
        model,
        path,
        model_version="test",
        training_data_sha256="a" * 64,
        metrics={},
        label_policy=model.label_policy,
    )
    restored, _ = load_model_artifact(path)
    np.testing.assert_allclose(prediction, restored.predict_success_probability(split.test))
    # Results and future outcomes are not accepted as prediction features.
    changed = split.test.copy()
    changed["success_label"] = 1 - changed["success_label"]
    np.testing.assert_allclose(prediction, restored.predict_success_probability(changed))


def test_small_real_snapshot_cannot_enter_comparison():
    with pytest.raises(ValueError, match="100 training"):
        select_success_model(pd.DataFrame(index=range(8)), pd.DataFrame(index=range(2)))


def test_calibration_reporting_and_paired_interval():
    y = np.array([0, 1, 0, 1])
    p = np.array([0.1, 0.9, 0.2, 0.8])
    assert sum(row["count"] for row in calibration_bins(y, p)) == 4
    result = paired_brier_interval(y, p, p)
    assert result["mean"] == result["lower_95"] == result["upper_95"] == 0


def test_rare_failure_reasons_use_smoothed_prior(plans, outcomes, failure_reasons):
    datasets = build_training_datasets(plans, outcomes, failure_reasons)
    examples = datasets.failure_examples
    targets = datasets.failure_targets.copy()
    targets.loc[:, :] = 0
    model = FailureReasonProbabilityModel().fit(examples, targets)
    model.select_on_validation(examples, targets, examples, targets)
    p = model.predict_reason_probabilities(examples).to_numpy()
    assert (p > 0).all() and (p < 1).all()
    assert set(model.selection.values()) == {"smoothed_prior"}
