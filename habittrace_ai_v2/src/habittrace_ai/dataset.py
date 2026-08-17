"""Build leakage-safe success and failure-reason training sets."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import pandas as pd

from habittrace_ai.contracts import (
    FAILURE_REASON_CODES,
    PLAN_TABLE_COLUMNS,
    REQUIRED_FAILURE_REASON_COLUMNS,
    REQUIRED_OUTCOME_COLUMNS,
    REQUIRED_PLAN_COLUMNS,
    require_columns,
)
from habittrace_ai.labels import derive_success_labels

UTC = timezone.utc


@dataclass(frozen=True)
class TrainingDatasets:
    """Aligned examples and labels for both V2 prediction tasks."""

    success_examples: pd.DataFrame
    failure_examples: pd.DataFrame
    failure_targets: pd.DataFrame


def _aware_utc(value: object, *, field: str) -> datetime:
    raw: Any = value
    if raw is None or pd.isna(raw):
        raise ValueError(f"{field} must be a timezone-aware datetime")
    result = pd.Timestamp(raw).to_pydatetime()
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError(f"{field} must be timezone-aware")
    return result.astimezone(UTC)


def _assert_unique(frame: pd.DataFrame, column: str, *, name: str) -> None:
    duplicated = frame[column].duplicated(keep=False)
    if duplicated.any():
        values = frame.loc[duplicated, column].astype(str).unique().tolist()
        raise ValueError(f"{name}.{column} must be unique; duplicates: {values[:3]}")


def _success_examples(plans: pd.DataFrame, outcomes: pd.DataFrame) -> pd.DataFrame:
    require_columns(plans.columns, REQUIRED_PLAN_COLUMNS, name="plans")
    require_columns(outcomes.columns, REQUIRED_OUTCOME_COLUMNS, name="outcomes")
    _assert_unique(plans, "id", name="plans")
    _assert_unique(outcomes, "id", name="outcomes")
    _assert_unique(outcomes, "plan_input_id", name="outcomes")

    outcome_labels = outcomes[["id", "plan_input_id", "recorded_at"]].copy()
    outcome_labels = outcome_labels.rename(
        columns={"id": "outcome_id", "recorded_at": "label_available_at"}
    )
    outcome_labels["label_available_at"] = outcome_labels["label_available_at"].map(
        lambda value: _aware_utc(value, field="outcomes.recorded_at")
    )
    outcome_labels["success_label"] = derive_success_labels(outcomes).to_numpy()

    available_plan_columns = [column for column in PLAN_TABLE_COLUMNS if column in plans.columns]
    examples = plans[available_plan_columns].merge(
        outcome_labels,
        how="inner",
        left_on="id",
        right_on="plan_input_id",
        validate="one_to_one",
    )
    return examples.drop(columns=["plan_input_id"]).reset_index(drop=True)


def _confirmed_reason_targets(
    success_examples: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    require_columns(
        failure_reasons.columns,
        REQUIRED_FAILURE_REASON_COLUMNS,
        name="failure_reasons",
    )

    confirmed = failure_reasons.loc[failure_reasons["user_confirmed"].eq(True)].copy()  # noqa: E712
    if confirmed.empty:
        empty_examples = (
            success_examples.iloc[0:0]
            .set_index("outcome_id")
            .drop(columns=["success_label"])
        )
        empty_targets = pd.DataFrame(
            index=pd.Index([], name="outcome_id"),
            columns=FAILURE_REASON_CODES,
            dtype="int8",
        )
        return empty_examples, empty_targets

    unknown_codes = sorted(set(confirmed["reason_code"].astype(str)) - set(FAILURE_REASON_CODES))
    if unknown_codes:
        raise ValueError(f"unknown confirmed reason_code values: {', '.join(unknown_codes)}")
    if confirmed[["outcome_id", "reason_code"]].duplicated().any():
        raise ValueError("confirmed outcome/reason pairs must be unique")

    known_outcomes = set(success_examples["outcome_id"].astype(str))
    missing_outcomes = sorted(set(confirmed["outcome_id"].astype(str)) - known_outcomes)
    if missing_outcomes:
        raise ValueError(f"confirmed reasons reference unknown outcomes: {missing_outcomes[:3]}")

    success_outcomes = set(
        success_examples.loc[success_examples["success_label"], "outcome_id"].astype(str)
    )
    invalid_successes = sorted(set(confirmed["outcome_id"].astype(str)) & success_outcomes)
    if invalid_successes:
        raise ValueError(f"successful outcomes cannot have failure labels: {invalid_successes[:3]}")

    primary_counts = confirmed.groupby("outcome_id")["is_primary"].apply(
        lambda values: int(values.eq(True).sum())  # noqa: E712
    )
    invalid_primary = primary_counts[primary_counts != 1]
    if not invalid_primary.empty:
        raise ValueError(
            "each labeled failed outcome must have exactly one confirmed primary reason"
        )

    confirmed["reason_created_at"] = confirmed["created_at"].map(
        lambda value: _aware_utc(value, field="failure_reasons.created_at")
    )
    reason_available_at = confirmed.groupby("outcome_id")["reason_created_at"].max()

    labeled_outcome_ids = confirmed["outcome_id"].drop_duplicates().tolist()
    labeled = success_examples.loc[
        success_examples["outcome_id"].isin(labeled_outcome_ids)
    ].copy()
    labeled = labeled.set_index("outcome_id").loc[labeled_outcome_ids]
    labeled["label_available_at"] = [
        max(
            _aware_utc(labeled.loc[outcome_id, "label_available_at"], field="recorded_at"),
            _aware_utc(reason_available_at.loc[outcome_id], field="reason_created_at"),
        )
        for outcome_id in labeled_outcome_ids
    ]

    targets = pd.crosstab(confirmed["outcome_id"], confirmed["reason_code"])
    targets = targets.reindex(index=labeled_outcome_ids, columns=FAILURE_REASON_CODES, fill_value=0)
    targets = targets.clip(upper=1).astype("int8")
    targets.index.name = "outcome_id"

    examples = labeled.drop(columns=["success_label"])
    if not examples.index.equals(targets.index):
        raise RuntimeError("failure examples and targets are not aligned")
    return examples, targets


def build_training_datasets(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> TrainingDatasets:
    """Create training sets while enforcing the V2 truth-source rules."""

    success_examples = _success_examples(plans, outcomes)
    failure_examples, failure_targets = _confirmed_reason_targets(
        success_examples,
        failure_reasons,
    )
    return TrainingDatasets(
        success_examples=success_examples,
        failure_examples=failure_examples,
        failure_targets=failure_targets,
    )
