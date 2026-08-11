"""Training-label rules derived from outcomes rather than persisted booleans."""

from __future__ import annotations

import numpy as np
import pandas as pd

from habittrace_ai.contracts import OUTCOME_STATUSES, require_columns

SUCCESS_LABEL_POLICY = 'outcome_status == "completed" and completion_ratio >= 0.8'
FAILURE_REASON_LABEL_POLICY = (
    "failed outcomes only; one primary plus zero or more secondary labels; "
    "all labels must be user_confirmed=true"
)


def derive_success_labels(outcomes: pd.DataFrame) -> pd.Series:
    """Return the initial success definition as a boolean Series."""

    require_columns(
        outcomes.columns,
        {"outcome_status", "completion_ratio"},
        name="outcomes",
    )
    statuses = outcomes["outcome_status"].astype("string")
    if statuses.isna().any():
        raise ValueError("outcome_status cannot be null")
    unknown = sorted(set(statuses.dropna().astype(str)) - OUTCOME_STATUSES)
    if unknown:
        raise ValueError(f"unknown outcome_status values: {', '.join(unknown)}")

    completion = pd.to_numeric(outcomes["completion_ratio"], errors="coerce")
    invalid_completion = (
        outcomes["completion_ratio"].isna()
        | completion.isna()
        | ~np.isfinite(completion)
        | completion.lt(0)
        | completion.gt(1)
    )
    if invalid_completion.any():
        raise ValueError("completion_ratio must be a finite number between zero and one")
    return (statuses.eq("completed") & completion.ge(0.8)).astype(bool)
