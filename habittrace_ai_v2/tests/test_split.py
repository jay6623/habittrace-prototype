from __future__ import annotations

import pandas as pd
import pytest

from habittrace_ai.split import temporal_split_aligned, temporal_train_validation_test_split


def test_split_is_chronological_even_when_input_is_shuffled(plans: pd.DataFrame) -> None:
    shuffled = plans.sample(frac=1.0, random_state=42)
    shuffled["label_available_at"] = shuffled["created_at"] + pd.Timedelta(hours=1)
    split = temporal_train_validation_test_split(shuffled)

    assert split.train["created_at"].max() <= split.validation["created_at"].min()
    assert split.validation["created_at"].max() <= split.test["created_at"].min()
    assert len(split.train) + len(split.validation) + len(split.test) == len(plans)


def test_split_rejects_naive_timestamps(plans: pd.DataFrame) -> None:
    changed = plans.iloc[:3].copy()
    changed["created_at"] = changed["created_at"].map(lambda value: value.replace(tzinfo=None))
    changed["label_available_at"] = plans.iloc[:3]["created_at"]
    with pytest.raises(ValueError, match="timezone-aware"):
        temporal_train_validation_test_split(changed)


def test_late_training_label_is_excluded(plans: pd.DataFrame) -> None:
    examples = plans.iloc[:12].copy()
    examples["label_available_at"] = examples["created_at"] + pd.Timedelta(hours=1)
    late_index = examples.index[0]
    examples.loc[late_index, "label_available_at"] = examples["created_at"].max() + pd.Timedelta(
        days=30
    )

    split = temporal_train_validation_test_split(examples)

    assert late_index not in split.train.index


def test_boundary_crossing_revision_lineage_is_excluded(plans: pd.DataFrame) -> None:
    examples = plans.iloc[:12].copy()
    examples["label_available_at"] = examples["created_at"] + pd.Timedelta(hours=1)
    root_id = examples.iloc[0]["id"]
    child_index = examples.index[-1]
    examples.loc[child_index, "parent_plan_input_id"] = root_id

    split = temporal_train_validation_test_split(examples)
    partitions = [set(partition["id"]) for partition in (split.train, split.validation, split.test)]

    assert root_id in split.excluded_lineages
    assert all(root_id not in partition for partition in partitions)
    assert all(examples.loc[child_index, "id"] not in partition for partition in partitions)
    assert split.train["created_at"].max() < split.validation["created_at"].min()
    assert split.validation["created_at"].max() < split.test["created_at"].min()


def test_validation_label_after_test_cutoff_is_excluded(plans: pd.DataFrame) -> None:
    examples = plans.iloc[:15].copy()
    examples["label_available_at"] = examples["created_at"] + pd.Timedelta(minutes=1)
    validation_index = examples.index[9]
    examples.loc[validation_index, "label_available_at"] = examples["created_at"].max()

    split = temporal_train_validation_test_split(examples)

    assert validation_index not in split.validation.index


def test_aligned_split_keeps_targets_attached(plans: pd.DataFrame) -> None:
    examples = plans.iloc[:12].copy()
    examples["label_available_at"] = examples["created_at"] + pd.Timedelta(hours=1)
    targets = pd.Series(range(len(examples)), index=examples.index)

    split = temporal_split_aligned(examples, targets)

    assert split.train_examples.index.equals(split.train_targets.index)
    assert split.validation_examples.index.equals(split.validation_targets.index)
    assert split.test_examples.index.equals(split.test_targets.index)
