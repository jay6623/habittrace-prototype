"""Shared scikit-learn preprocessing for plan-time features."""

from __future__ import annotations

from typing import Any

from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

from habittrace_ai.features import CATEGORICAL_FEATURE_COLUMNS, NUMERIC_FEATURE_COLUMNS


def logistic_pipeline() -> Pipeline[Any]:
    numeric = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
        ]
    )
    categorical = Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="most_frequent")),
            ("one_hot", OneHotEncoder(handle_unknown="ignore")),
        ]
    )
    preprocessing = ColumnTransformer(
        transformers=[
            ("numeric", numeric, list(NUMERIC_FEATURE_COLUMNS)),
            ("categorical", categorical, list(CATEGORICAL_FEATURE_COLUMNS)),
        ]
    )
    return Pipeline(
        steps=[
            ("preprocessing", preprocessing),
            (
                "classifier",
                LogisticRegression(
                    max_iter=1_000,
                    random_state=42,
                ),
            ),
        ]
    )
