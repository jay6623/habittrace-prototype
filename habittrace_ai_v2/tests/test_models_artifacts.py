from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from habittrace_ai.artifacts import (
    dataframe_sha256,
    load_model_artifact,
    manifest_path,
    save_model_artifact,
)
from habittrace_ai.dataset import build_training_datasets
from habittrace_ai.evaluation import evaluate_binary_probabilities
from habittrace_ai.labels import SUCCESS_LABEL_POLICY
from habittrace_ai.models import FailureReasonProbabilityModel, SuccessProbabilityModel


def _datasets(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
):
    return build_training_datasets(plans, outcomes, failure_reasons)


def test_success_probability_model_smoke(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    examples = _datasets(plans, outcomes, failure_reasons).success_examples
    model = SuccessProbabilityModel().fit(examples, examples["success_label"])
    probabilities = model.predict_success_probability(examples.iloc[:5])
    assert probabilities.shape == (5,)
    assert np.all((0 <= probabilities) & (probabilities <= 1))
    metrics = evaluate_binary_probabilities(
        examples["success_label"],
        model.predict_success_probability(examples),
    )
    assert metrics["brier_score"] is not None

    invalid_labels = examples["success_label"].astype(float)
    invalid_labels.iloc[0] = 0.5
    with pytest.raises(ValueError, match="binary"):
        SuccessProbabilityModel().fit(examples, invalid_labels)


def test_failure_reason_model_outputs_independent_probabilities(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    datasets = _datasets(plans, outcomes, failure_reasons)
    model = FailureReasonProbabilityModel().fit(
        datasets.failure_examples,
        datasets.failure_targets,
    )
    probabilities = model.predict_reason_probabilities(datasets.failure_examples.iloc[:4])
    assert probabilities.shape == (4, 8)
    assert np.all((0 <= probabilities.to_numpy()) & (probabilities.to_numpy() <= 1))
    # Independent multi-label probabilities are deliberately not normalized to sum to one.
    assert not np.allclose(probabilities.sum(axis=1).to_numpy(), 1.0)

    shuffled_targets = datasets.failure_targets.sample(frac=1.0, random_state=42)
    with pytest.raises(ValueError, match="ordered index"):
        FailureReasonProbabilityModel().fit(
            datasets.failure_examples,
            shuffled_targets,
        )

    invalid_targets = datasets.failure_targets.astype(float)
    invalid_targets.iloc[0, 0] = 0.5
    with pytest.raises(ValueError, match="binary"):
        FailureReasonProbabilityModel().fit(
            datasets.failure_examples,
            invalid_targets,
        )


def test_artifact_round_trip_and_checksum(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    examples = _datasets(plans, outcomes, failure_reasons).success_examples
    model = SuccessProbabilityModel().fit(examples, examples["success_label"])
    before = model.predict_success_probability(examples.iloc[:3])
    path = Path(__file__).with_name("_artifact_test.joblib")
    metadata_path = manifest_path(path)
    try:
        manifest = save_model_artifact(
            model,
            path,
            model_version="success-v0.1.0",
            training_data_sha256=dataframe_sha256(examples),
            metrics={"brier_score": 0.2},
            label_policy=SUCCESS_LABEL_POLICY,
        )
        loaded, loaded_manifest = load_model_artifact(
            path,
            expected_model_type=SuccessProbabilityModel.model_type,
        )
        after = loaded.predict_success_probability(examples.iloc[:3])

        assert manifest == loaded_manifest
        np.testing.assert_allclose(before, after)

        with path.open("ab") as stream:
            stream.write(b"tampered")
        with pytest.raises(ValueError, match="checksum"):
            load_model_artifact(path)
    finally:
        path.unlink(missing_ok=True)
        metadata_path.unlink(missing_ok=True)


def test_dataframe_hash_preserves_float_precision() -> None:
    first = pd.DataFrame({"value": [0.123456789011]})
    second = pd.DataFrame({"value": [0.123456789019]})
    assert dataframe_sha256(first) != dataframe_sha256(second)


def test_dataframe_hash_preserves_column_name_type() -> None:
    numeric_name = pd.DataFrame({1: ["value"]})
    string_name = pd.DataFrame({"1": ["value"]})
    assert dataframe_sha256(numeric_name) != dataframe_sha256(string_name)


def test_artifact_rejects_wrong_label_policy(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> None:
    examples = _datasets(plans, outcomes, failure_reasons).success_examples
    model = SuccessProbabilityModel().fit(examples, examples["success_label"])
    path = Path(__file__).with_name("_artifact_test.joblib")
    try:
        with pytest.raises(ValueError, match="label policy"):
            save_model_artifact(
                model,
                path,
                model_version="success-v0.1.0",
                training_data_sha256=dataframe_sha256(examples),
                metrics={},
                label_policy="wrong policy",
            )
    finally:
        path.unlink(missing_ok=True)
        manifest_path(path).unlink(missing_ok=True)


def test_artifact_rejects_unfitted_model() -> None:
    path = Path(__file__).with_name("_artifact_test.joblib")
    try:
        with pytest.raises(ValueError, match="fitted"):
            save_model_artifact(
                SuccessProbabilityModel(),
                path,
                model_version="success-v0.1.0",
                training_data_sha256="0" * 64,
                metrics={},
                label_policy=SUCCESS_LABEL_POLICY,
            )
    finally:
        path.unlink(missing_ok=True)
        manifest_path(path).unlink(missing_ok=True)
