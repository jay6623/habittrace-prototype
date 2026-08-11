"""Versioned model persistence with integrity metadata."""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, TypeAlias

import joblib
import numpy as np
import pandas as pd

ARTIFACT_FORMAT_VERSION = 1
JSONValue: TypeAlias = (
    str | int | float | bool | None | list["JSONValue"] | dict[str, "JSONValue"]
)
REQUIRED_MANIFEST_FIELDS: frozenset[str] = frozenset(
    {
        "artifact_format_version",
        "model_type",
        "model_version",
        "created_at",
        "feature_columns",
        "label_policy",
        "training_data_sha256",
        "metrics",
        "model_sha256",
    }
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dataframe_sha256(frame: pd.DataFrame) -> str:
    """Hash values, index, column order, and dtypes without JSON float rounding."""

    digest = hashlib.sha256()
    schema = {
        "columns": [
            {
                "name_type": f"{type(column).__module__}.{type(column).__qualname__}",
                "name_repr": repr(column),
                "dtype": str(dtype),
            }
            for column, dtype in frame.dtypes.items()
        ],
        "index_names": [
            (
                None
                if name is None
                else {
                    "name_type": f"{type(name).__module__}.{type(name).__qualname__}",
                    "name_repr": repr(name),
                }
            )
            for name in frame.index.names
        ],
        "index_dtypes": [str(frame.index.dtype)],
    }
    digest.update(json.dumps(schema, separators=(",", ":")).encode("utf-8"))
    value_hashes = pd.util.hash_pandas_object(frame, index=True, categorize=False)
    digest.update(np.asarray(value_hashes, dtype="<u8").tobytes())
    return digest.hexdigest()


def manifest_path(model_path: str | Path) -> Path:
    path = Path(model_path)
    return path.with_suffix(path.suffix + ".manifest.json")


def save_model_artifact(
    model: Any,
    model_path: str | Path,
    *,
    model_version: str,
    training_data_sha256: str,
    metrics: dict[str, JSONValue],
    label_policy: str,
) -> dict[str, Any]:
    """Persist a model and a reviewable manifest beside it."""

    expected_label_policy = getattr(model, "label_policy", None)
    if not expected_label_policy or label_policy != expected_label_policy:
        raise ValueError("label policy does not match the model contract")
    is_fitted = getattr(model, "is_fitted", None)
    if not callable(is_fitted) or not is_fitted():
        raise ValueError("only a fitted model can be saved as an artifact")

    path = Path(model_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, path)
    manifest: dict[str, Any] = {
        "artifact_format_version": ARTIFACT_FORMAT_VERSION,
        "model_type": str(model.model_type),
        "model_version": model_version,
        "created_at": datetime.now(UTC).isoformat(),
        "feature_columns": list(model.feature_columns),
        "label_policy": label_policy,
        "training_data_sha256": training_data_sha256,
        "metrics": metrics,
        "model_sha256": _sha256(path),
    }
    manifest_path(path).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return manifest


def load_model_artifact(
    model_path: str | Path,
    *,
    expected_model_type: str | None = None,
) -> tuple[Any, dict[str, Any]]:
    """Verify checksum and contract metadata before deserializing a model."""

    path = Path(model_path)
    metadata_path = manifest_path(path)
    if not path.is_file() or not metadata_path.is_file():
        raise FileNotFoundError("both model and manifest files are required")
    raw_metadata: Any = json.loads(metadata_path.read_text(encoding="utf-8"))
    if not isinstance(raw_metadata, dict):
        raise ValueError("artifact manifest root must be a JSON object")
    metadata: dict[str, Any] = raw_metadata
    missing_fields = sorted(REQUIRED_MANIFEST_FIELDS - set(metadata))
    if missing_fields:
        raise ValueError(f"artifact manifest is missing fields: {', '.join(missing_fields)}")
    if metadata.get("artifact_format_version") != ARTIFACT_FORMAT_VERSION:
        raise ValueError("unsupported artifact format version")
    if not isinstance(metadata.get("model_version"), str) or not metadata["model_version"]:
        raise ValueError("artifact manifest has an invalid model version")
    if not isinstance(metadata.get("label_policy"), str) or not metadata["label_policy"]:
        raise ValueError("artifact manifest has an invalid label policy")
    training_hash = metadata.get("training_data_sha256")
    if not isinstance(training_hash, str) or len(training_hash) != 64:
        raise ValueError("artifact manifest has an invalid training data hash")
    if metadata.get("model_sha256") != _sha256(path):
        raise ValueError("model artifact checksum mismatch")
    if expected_model_type is not None and metadata.get("model_type") != expected_model_type:
        raise ValueError("model artifact type mismatch")

    model = joblib.load(path)
    if metadata.get("model_type") != getattr(model, "model_type", None):
        raise ValueError("manifest and serialized model type do not match")
    if metadata.get("feature_columns") != list(getattr(model, "feature_columns", ())):
        raise ValueError("manifest and serialized feature schemas do not match")
    if metadata.get("label_policy") != getattr(model, "label_policy", None):
        raise ValueError("manifest and serialized label policies do not match")
    is_fitted = getattr(model, "is_fitted", None)
    if not callable(is_fitted) or not is_fitted():
        raise ValueError("serialized model is not fitted")
    return model, metadata
