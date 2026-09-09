"""Export AI Supabase truth tables into a validated training-data snapshot.

The exporter is intentionally read-only. It fetches plan inputs, outcomes, and
user-confirmed failure reasons through the Supabase REST API, then writes CSV
files that can be passed directly to :mod:`habittrace_ai.train`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import pandas as pd

from habittrace_ai.contracts import (
    REQUIRED_FAILURE_REASON_COLUMNS,
    REQUIRED_OUTCOME_COLUMNS,
    REQUIRED_PLAN_COLUMNS,
)
from habittrace_ai.dataset import build_training_datasets

UTC = UTC

TABLES = {
    "plans": ("ai_plan_inputs", "created_at", REQUIRED_PLAN_COLUMNS),
    "outcomes": ("ai_plan_outcomes", "recorded_at", REQUIRED_OUTCOME_COLUMNS),
    "failure_reasons": (
        "ai_outcome_failure_reasons",
        "created_at",
        REQUIRED_FAILURE_REASON_COLUMNS,
    ),
}


def _load_env_file(path: Path) -> None:
    """Load simple KEY=VALUE lines without overwriting existing environment values."""

    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, value)


def _rest_url(raw_url: str) -> str:
    base = raw_url.strip().rstrip("/")
    if base.endswith("/rest/v1"):
        return base
    return f"{base}/rest/v1"


def _fetch_table(
    base_url: str,
    service_key: str,
    table_name: str,
    order_column: str,
    *,
    page_size: int,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        query = urlencode(
            {
                "select": "*",
                "order": f"{order_column}.asc",
                "limit": str(page_size),
                "offset": str(offset),
            }
        )
        request = Request(
            f"{base_url}/{table_name}?{query}",
            headers={
                "Accept": "application/json",
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
            },
            method="GET",
        )
        try:
            with urlopen(request, timeout=30) as response:  # noqa: S310
                payload = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"AI Supabase request failed for {table_name} ({exc.code}): {detail[:500]}"
            ) from exc
        except URLError as exc:
            raise RuntimeError(f"AI Supabase network request failed: {exc.reason}") from exc

        if not isinstance(payload, list):
            raise RuntimeError(f"AI Supabase returned an unexpected response for {table_name}.")
        rows.extend(row for row in payload if isinstance(row, dict))
        if len(payload) < page_size:
            return rows
        offset += page_size


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _quality_report(
    plans: pd.DataFrame,
    outcomes: pd.DataFrame,
    failure_reasons: pd.DataFrame,
) -> dict[str, Any]:
    try:
        datasets = build_training_datasets(plans, outcomes, failure_reasons)
    except (TypeError, ValueError, KeyError) as exc:
        return {
            "valid": False,
            "error": str(exc),
            "success_examples": 0,
            "failure_examples": 0,
            "failure_reason_labels": 0,
        }
    return {
        "valid": True,
        "error": None,
        "success_examples": len(datasets.success_examples),
        "failure_examples": len(datasets.failure_examples),
        "failure_reason_labels": int(datasets.failure_targets.to_numpy().sum()),
    }


def export_snapshot(
    *,
    ai_url: str,
    service_key: str,
    outdir: Path,
    page_size: int,
    allow_invalid: bool,
) -> dict[str, Any]:
    if not service_key.strip():
        raise ValueError("AI_SUPABASE_SERVICE_ROLE_KEY is required")
    if page_size < 1 or page_size > 1000:
        raise ValueError("page_size must be between 1 and 1000")

    base_url = _rest_url(ai_url)
    frames: dict[str, pd.DataFrame] = {}
    for output_name, (table_name, order_column, required_columns) in TABLES.items():
        rows = _fetch_table(
            base_url,
            service_key,
            table_name,
            order_column,
            page_size=page_size,
        )
        frame = pd.DataFrame(rows)
        if frame.empty:
            frame = pd.DataFrame(columns=sorted(required_columns))
        frames[output_name] = frame

    # Synthetic fixtures are for local development only and must not silently
    # enter a real-data candidate model. Keep their dependent rows out too.
    synthetic_plan_ids = set(
        frames["plans"]
        .loc[
            frames["plans"].get("input_source", pd.Series(dtype=object)).eq("synthetic"),
            "id",
        ]
        .astype(str)
    )
    if synthetic_plan_ids:
        frames["plans"] = (
            frames["plans"].loc[~frames["plans"]["id"].astype(str).isin(synthetic_plan_ids)].copy()
        )
        real_plan_ids = set(frames["plans"]["id"].astype(str))
        frames["outcomes"] = (
            frames["outcomes"]
            .loc[frames["outcomes"]["plan_input_id"].astype(str).isin(real_plan_ids)]
            .copy()
        )
        real_outcome_ids = set(frames["outcomes"]["id"].astype(str))
        frames["failure_reasons"] = (
            frames["failure_reasons"]
            .loc[frames["failure_reasons"]["outcome_id"].astype(str).isin(real_outcome_ids)]
            .copy()
        )

    outdir.mkdir(parents=True, exist_ok=True)
    paths = {name: outdir / f"{name}.csv" for name in ("plans", "outcomes", "failure_reasons")}
    for name, path in paths.items():
        frames[name].to_csv(path, index=False)

    quality = _quality_report(frames["plans"], frames["outcomes"], frames["failure_reasons"])
    report = {
        "exported_at": datetime.now(UTC).isoformat(),
        "source": "ai_supabase_rest_read_only",
        "tables": {
            name: {"rows": len(frame), "sha256": _sha256(paths[name])}
            for name, frame in frames.items()
        },
        "quality": quality,
    }
    (outdir / "manifest.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not quality["valid"] and not allow_invalid:
        raise RuntimeError(f"Export completed but quality validation failed: {quality['error']}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ai-url", default=os.getenv("AI_SUPABASE_URL"))
    parser.add_argument("--service-key", default=os.getenv("AI_SUPABASE_SERVICE_ROLE_KEY"))
    parser.add_argument(
        "--env-file",
        type=Path,
        default=None,
        help="Optional .env file; values do not override existing environment variables.",
    )
    parser.add_argument(
        "--outdir", type=Path, default=Path("data/real"), help="Output snapshot directory."
    )
    parser.add_argument("--page-size", type=int, default=500)
    parser.add_argument(
        "--allow-invalid",
        action="store_true",
        help="Write files and exit zero even when training-data validation fails.",
    )
    args = parser.parse_args()

    if args.env_file:
        _load_env_file(args.env_file)
    elif Path("../backend/.env").is_file():
        _load_env_file(Path("../backend/.env"))

    ai_url = args.ai_url or os.getenv("AI_SUPABASE_URL")
    service_key = args.service_key or os.getenv("AI_SUPABASE_SERVICE_ROLE_KEY")
    if not ai_url:
        raise SystemExit("AI_SUPABASE_URL is required (or pass --ai-url).")
    if not service_key:
        raise SystemExit("AI_SUPABASE_SERVICE_ROLE_KEY is required (or pass --service-key).")

    try:
        report = export_snapshot(
            ai_url=ai_url,
            service_key=service_key,
            outdir=args.outdir,
            page_size=args.page_size,
            allow_invalid=args.allow_invalid,
        )
    except (RuntimeError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
