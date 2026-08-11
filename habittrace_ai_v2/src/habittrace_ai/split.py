"""Leakage-aware chronological splitting utilities."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

import pandas as pd


@dataclass(frozen=True)
class TemporalSplit:
    train: pd.DataFrame
    validation: pd.DataFrame
    test: pd.DataFrame
    excluded_lineages: tuple[str, ...] = ()


@dataclass(frozen=True)
class AlignedTemporalSplit:
    train_examples: pd.DataFrame
    train_targets: pd.Series | pd.DataFrame
    validation_examples: pd.DataFrame
    validation_targets: pd.Series | pd.DataFrame
    test_examples: pd.DataFrame
    test_targets: pd.Series | pd.DataFrame
    excluded_lineages: tuple[str, ...] = ()


def _aware_utc(value: object, *, column: str) -> datetime:
    raw: Any = value
    if raw is None or pd.isna(raw):
        raise ValueError(f"{column} cannot contain null timestamps")
    result = pd.Timestamp(raw).to_pydatetime()
    if result.tzinfo is None or result.utcoffset() is None:
        raise ValueError(f"{column} must contain timezone-aware timestamps")
    return result.astimezone(UTC)


def _lineage_roots(examples: pd.DataFrame) -> list[str]:
    if "id" not in examples.columns or "parent_plan_input_id" not in examples.columns:
        return [f"row:{position}" for position in range(len(examples))]

    identifiers = examples["id"].astype(str)
    if identifiers.duplicated().any():
        raise ValueError("id must be unique when lineage-aware splitting is enabled")
    parent_by_id = {
        str(identifier): (
            None if parent is None or pd.isna(parent) else str(parent)
        )
        for identifier, parent in zip(
            examples["id"],
            examples["parent_plan_input_id"],
            strict=True,
        )
    }

    def find_root(identifier: str) -> str:
        visited: set[str] = set()
        current = identifier
        while True:
            if current in visited:
                raise ValueError("plan revision lineage contains a cycle")
            visited.add(current)
            parent = parent_by_id.get(current)
            if parent is None:
                return current
            if parent not in parent_by_id:
                return parent
            current = parent

    return [find_root(identifier) for identifier in identifiers]


def _best_unit_boundary(
    cumulative_counts: list[int],
    *,
    target_count: float,
    first_boundary: int,
    last_boundary: int,
) -> int:
    """Return an exclusive unit boundary nearest the requested row count."""

    return min(
        range(first_boundary, last_boundary + 1),
        key=lambda boundary: abs(cumulative_counts[boundary - 1] - target_count),
    )


def temporal_train_validation_test_split(
    examples: pd.DataFrame,
    *,
    timestamp_column: str = "created_at",
    label_available_column: str = "label_available_at",
    train_fraction: float = 0.6,
    validation_fraction: float = 0.2,
) -> TemporalSplit:
    """Split by time while keeping revision lineages and timestamp ties together.

    Training rows whose labels were not available at the validation cutoff are
    removed. This prevents a late-recorded outcome from leaking future truth
    into an earlier offline training snapshot.
    """

    for column in (timestamp_column, label_available_column):
        if column not in examples.columns:
            raise ValueError(f"missing timestamp column: {column}")
    if len(examples) < 3:
        raise ValueError("at least three examples are required for a three-way split")
    if not 0.0 < train_fraction < 1.0 or not 0.0 < validation_fraction < 1.0:
        raise ValueError("split fractions must be between zero and one")
    if train_fraction + validation_fraction >= 1.0:
        raise ValueError("train_fraction + validation_fraction must be less than one")

    working = examples.copy()
    working["_prediction_time"] = working[timestamp_column].map(
        lambda value: _aware_utc(value, column=timestamp_column)
    )
    working["_label_available_time"] = working[label_available_column].map(
        lambda value: _aware_utc(value, column=label_available_column)
    )
    working["_lineage_root"] = _lineage_roots(working)

    # Timestamp ties are indivisible units. Lineages are handled after raw time
    # boundaries are chosen; moving an old root forward with a recent child
    # would make later training rows precede an earlier test row.
    working["_unit_time"] = working["_prediction_time"]
    unit_times = sorted(working["_unit_time"].unique())
    if len(unit_times) < 3:
        raise ValueError(
            "at least three distinct lineage/timestamp groups are required for a split"
        )

    unit_counts = [int(working["_unit_time"].eq(value).sum()) for value in unit_times]
    cumulative_counts: list[int] = []
    total = 0
    for count in unit_counts:
        total += count
        cumulative_counts.append(total)

    train_boundary = _best_unit_boundary(
        cumulative_counts,
        target_count=len(working) * train_fraction,
        first_boundary=1,
        last_boundary=len(unit_times) - 2,
    )
    validation_boundary = _best_unit_boundary(
        cumulative_counts,
        target_count=len(working) * (train_fraction + validation_fraction),
        first_boundary=train_boundary + 1,
        last_boundary=len(unit_times) - 1,
    )

    train_units = set(unit_times[:train_boundary])
    validation_units = set(unit_times[train_boundary:validation_boundary])
    test_units = set(unit_times[validation_boundary:])
    validation_cutoff = min(validation_units)
    test_cutoff = min(test_units)

    working["_partition"] = "test"
    working.loc[working["_unit_time"].isin(train_units), "_partition"] = "train"
    working.loc[working["_unit_time"].isin(validation_units), "_partition"] = (
        "validation"
    )
    lineage_partition_counts = working.groupby("_lineage_root")["_partition"].nunique()
    excluded_lineages = tuple(
        sorted(lineage_partition_counts[lineage_partition_counts > 1].index.astype(str))
    )
    if excluded_lineages:
        working = working.loc[~working["_lineage_root"].isin(excluded_lineages)]

    train = working.loc[
        working["_unit_time"].isin(train_units)
        & working["_label_available_time"].lt(validation_cutoff)
    ]
    validation = working.loc[
        working["_unit_time"].isin(validation_units)
        & working["_label_available_time"].lt(test_cutoff)
    ]
    test = working.loc[working["_unit_time"].isin(test_units)]
    if train.empty:
        raise ValueError("no training labels were available before the validation cutoff")
    if validation.empty or test.empty:
        raise ValueError("lineage and label cutoffs left an empty evaluation partition")

    helper_columns = [
        "_prediction_time",
        "_label_available_time",
        "_lineage_root",
        "_unit_time",
        "_partition",
    ]

    def finalize(frame: pd.DataFrame) -> pd.DataFrame:
        return frame.sort_values("_prediction_time", kind="stable").drop(
            columns=helper_columns
        )

    return TemporalSplit(
        train=finalize(train),
        validation=finalize(validation),
        test=finalize(test),
        excluded_lineages=excluded_lineages,
    )


def temporal_split_aligned(
    examples: pd.DataFrame,
    targets: pd.Series | pd.DataFrame,
    *,
    timestamp_column: str = "created_at",
    label_available_column: str = "label_available_at",
    train_fraction: float = 0.6,
    validation_fraction: float = 0.2,
) -> AlignedTemporalSplit:
    """Split examples and labels together and preserve their exact row identity."""

    if not examples.index.is_unique or not targets.index.is_unique:
        raise ValueError("example and target indexes must be unique")
    if not examples.index.equals(targets.index):
        raise ValueError("examples and targets must have the same ordered index")
    split = temporal_train_validation_test_split(
        examples,
        timestamp_column=timestamp_column,
        label_available_column=label_available_column,
        train_fraction=train_fraction,
        validation_fraction=validation_fraction,
    )
    return AlignedTemporalSplit(
        train_examples=split.train,
        train_targets=targets.loc[split.train.index],
        validation_examples=split.validation,
        validation_targets=targets.loc[split.validation.index],
        test_examples=split.test,
        test_targets=targets.loc[split.test.index],
        excluded_lineages=split.excluded_lineages,
    )
