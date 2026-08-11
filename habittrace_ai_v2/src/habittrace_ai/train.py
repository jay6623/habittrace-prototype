"""Command-line training runner for the AI V2 baseline models."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import pandas as pd

from habittrace_ai.artifacts import save_model_artifact
from habittrace_ai.dataset import build_training_datasets
from habittrace_ai.evaluation import evaluate_binary_probabilities, evaluate_failure_probabilities
from habittrace_ai.models.failure_reason import FailureReasonProbabilityModel
from habittrace_ai.models.success import SuccessProbabilityModel
from habittrace_ai.split import temporal_split_aligned, temporal_train_validation_test_split


def _file_sha256(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        digest.update(path.name.encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def _load_csv(path: Path, name: str) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"{name} CSV not found: {path}")
    return pd.read_csv(path)


def train(
    plans_path: Path,
    outcomes_path: Path,
    failure_reasons_path: Path,
    outdir: Path,
    model_version: str,
) -> dict[str, Any]:
    source_paths = [plans_path, outcomes_path, failure_reasons_path]
    plans = _load_csv(plans_path, "plans")
    outcomes = _load_csv(outcomes_path, "outcomes")
    failure_reasons = _load_csv(failure_reasons_path, "failure reasons")
    datasets = build_training_datasets(plans, outcomes, failure_reasons)

    success_split = temporal_train_validation_test_split(
        datasets.success_examples,
        timestamp_column="created_at",
        label_available_column="label_available_at",
    )
    failure_split = temporal_split_aligned(
        datasets.failure_examples,
        datasets.failure_targets,
        timestamp_column="created_at",
        label_available_column="label_available_at",
    )
    assert isinstance(failure_split.train_targets, pd.DataFrame)
    assert isinstance(failure_split.validation_targets, pd.DataFrame)
    assert isinstance(failure_split.test_targets, pd.DataFrame)

    success_model = SuccessProbabilityModel().fit(
        success_split.train,
        success_split.train["success_label"],
    )
    failure_model = FailureReasonProbabilityModel().fit(
        failure_split.train_examples,
        failure_split.train_targets,
    )

    success_validation_probability = success_model.predict_success_probability(
        success_split.validation
    )
    success_test_probability = success_model.predict_success_probability(success_split.test)
    failure_validation_probability = failure_model.predict_reason_probabilities(
        failure_split.validation_examples
    )
    failure_test_probability = failure_model.predict_reason_probabilities(
        failure_split.test_examples
    )
    metrics: dict[str, Any] = {
        "success": {
            "validation": evaluate_binary_probabilities(
                success_split.validation["success_label"], success_validation_probability
            ),
            "test": evaluate_binary_probabilities(
                success_split.test["success_label"], success_test_probability
            ),
        },
        "failure_reason": {
            "validation": evaluate_failure_probabilities(
                failure_split.validation_targets, failure_validation_probability
            ),
            "test": evaluate_failure_probabilities(
                failure_split.test_targets, failure_test_probability
            ),
        },
        "rows": {
            "success_train": len(success_split.train),
            "success_validation": len(success_split.validation),
            "success_test": len(success_split.test),
            "failure_train": len(failure_split.train_examples),
            "failure_validation": len(failure_split.validation_examples),
            "failure_test": len(failure_split.test_examples),
        },
    }
    training_hash = _file_sha256(source_paths)
    outdir.mkdir(parents=True, exist_ok=True)
    success_manifest = save_model_artifact(
        success_model,
        outdir / "success_model.joblib",
        model_version=model_version,
        training_data_sha256=training_hash,
        metrics=metrics["success"],
        label_policy=success_model.label_policy,
    )
    failure_manifest = save_model_artifact(
        failure_model,
        outdir / "failure_reason_model.joblib",
        model_version=model_version,
        training_data_sha256=training_hash,
        metrics=metrics["failure_reason"],
        label_policy=failure_model.label_policy,
    )
    metrics["artifacts"] = {
        "success": success_manifest,
        "failure_reason": failure_manifest,
    }
    (outdir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2, sort_keys=True, default=str) + "\n",
        encoding="utf-8",
    )
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plans", type=Path, required=True)
    parser.add_argument("--outcomes", type=Path, required=True)
    parser.add_argument("--failure-reasons", type=Path, required=True)
    parser.add_argument("--outdir", type=Path, default=Path("artifacts"))
    parser.add_argument("--model-version", default="synthetic-baseline-1")
    args = parser.parse_args()
    result = train(
        args.plans,
        args.outcomes,
        args.failure_reasons,
        args.outdir,
        args.model_version,
    )
    print(json.dumps(result["rows"], indent=2, sort_keys=True))
    print(f"artifacts written to {args.outdir}")


if __name__ == "__main__":
    main()
