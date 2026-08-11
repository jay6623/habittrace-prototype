"""Generate clearly synthetic AI V2 training exports.

This data is for pipeline development only. It is not observed human data and
must never be presented as a production model evaluation set.
"""

from __future__ import annotations

import argparse
import json
import math
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

import numpy as np
import pandas as pd

from habittrace_ai.contracts import FAILURE_REASON_CODES


def _sigmoid(value: float) -> float:
    return 1.0 / (1.0 + math.exp(-value))


def generate(n_rows: int, seed: int) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    rng = np.random.default_rng(seed)
    base = datetime(2025, 1, 1, 8, tzinfo=UTC)
    categories = np.array(["study", "work", "health", "chores", "creative", "social"])
    timezones = np.array(["America/Denver", "America/New_York", "Europe/London", "Asia/Seoul"])
    plans: list[dict[str, object]] = []
    outcomes: list[dict[str, object]] = []
    reasons: list[dict[str, object]] = []

    for index in range(n_rows):
        plan_id = str(uuid5(NAMESPACE_URL, f"habittrace-synthetic-plan-{seed}-{index}"))
        user_id = str(uuid5(NAMESPACE_URL, f"habittrace-synthetic-user-{index % 40}"))
        planned_start = base + timedelta(hours=index * 9 + int(rng.integers(0, 4)))
        created_at = planned_start - timedelta(hours=int(rng.integers(2, 72)))
        duration = int(
            rng.choice([20, 30, 45, 60, 75, 90, 120], p=[.12, .18, .2, .2, .14, .1, .06])
        )
        importance = int(rng.integers(1, 6))
        difficulty = int(rng.integers(1, 6))
        required_energy = int(rng.integers(1, 6))
        required_focus = int(rng.integers(1, 6))
        current_energy = None if index % 19 == 0 else int(rng.integers(1, 6))
        current_focus = None if index % 23 == 0 else int(rng.integers(1, 6))
        sleep_hours = (
            None
            if index % 29 == 0
            else round(float(np.clip(rng.normal(7.0, 1.2), 4.0, 10.0)), 2)
        )
        stress_level = None if index % 31 == 0 else int(rng.integers(1, 6))
        tasks_before = int(rng.integers(0, 8))
        planned_before = tasks_before * int(rng.integers(20, 70))
        daily_minutes = planned_before + duration + int(rng.integers(0, 240))
        gap = None if tasks_before == 0 else int(rng.integers(5, 121))
        readiness_gap = (
            required_energy - (current_energy or 3)
            + required_focus
            - (current_focus or 3)
        )
        stress = stress_level or 3
        logit = (
            2.0
            - 0.42 * readiness_gap
            - 0.22 * (difficulty - 3)
            - 0.012 * max(duration - 45, 0)
            - 0.16 * stress
            - 0.004 * max(daily_minutes - 360, 0)
            - 0.08 * tasks_before
            + rng.normal(0, 0.65)
        )
        success_probability = _sigmoid(logit)
        completed = bool(rng.random() < success_probability)
        if completed:
            status = "completed"
            ratio = round(float(rng.uniform(0.82, 1.0)), 5)
        elif rng.random() < 0.25:
            status = "abandoned"
            ratio = 0.0
        else:
            status = "partial"
            ratio = round(float(rng.uniform(0.15, 0.75)), 5)

        outcome_id = str(uuid5(NAMESPACE_URL, f"habittrace-synthetic-outcome-{seed}-{index}"))
        recorded_at = planned_start + timedelta(minutes=int(rng.integers(15, 240)))
        plans.append({
            "id": plan_id,
            "user_id": user_id,
            "parent_plan_input_id": None,
            "input_source": "user",
            "title": f"Synthetic {categories[index % len(categories)]} task {index + 1}",
            "description": "Synthetic training example; not observed human data.",
            "category": str(rng.choice(categories)),
            "planned_start": planned_start.isoformat(),
            "planned_duration_minutes": duration,
            "deadline_at": (planned_start + timedelta(hours=int(rng.integers(2, 10)))).isoformat(),
            "importance": importance,
            "difficulty": difficulty,
            "required_energy": required_energy,
            "required_focus": required_focus,
            "current_energy": current_energy,
            "current_focus": current_focus,
            "sleep_hours": sleep_hours,
            "stress_level": stress_level,
            "tasks_before_count": tasks_before,
            "planned_minutes_before": planned_before,
            "daily_planned_minutes": daily_minutes,
            "minutes_since_previous": gap,
            "timezone_name": str(rng.choice(timezones)),
            "is_fixed_time": bool(index % 3 == 0),
            "created_at": created_at.isoformat(),
        })
        actual_start = planned_start + timedelta(minutes=int(rng.integers(0, 20)))
        outcomes.append({
            "id": outcome_id,
            "plan_input_id": plan_id,
            "outcome_status": status,
            "actual_start": actual_start.isoformat(),
            "actual_end": (
                actual_start + timedelta(minutes=max(1, int(duration * max(ratio, 0.2))))
            ).isoformat(),
            "active_minutes": max(0, int(duration * ratio)),
            "completion_ratio": ratio,
            "interruption_count": int(rng.integers(0, 4)),
            "stopped_early": status != "completed",
            "user_note": "Synthetic training example.",
            "recorded_at": recorded_at.isoformat(),
        })

        if status != "completed" or ratio < 0.8:
            signals = {
                "low_readiness": readiness_gap + rng.normal(0, 0.5),
                "schedule_overload": (daily_minutes - 360) / 90 + rng.normal(0, 0.5),
                "underestimated_time": (duration - 60) / 30 + rng.normal(0, 0.5),
                "interruption": int(outcomes[-1]["interruption_count"]) * 0.8 + rng.normal(0, 0.4),
                "unexpected_event": rng.normal(0.0, 1.0),
                "unclear_plan": (6 - importance) / 3 + rng.normal(0, 0.5),
                "task_too_difficult": (difficulty - 3) + rng.normal(0, 0.5),
                "other": rng.normal(0.0, 0.7),
            }
            primary = max(FAILURE_REASON_CODES, key=lambda code: signals[code])
            # Force every class into the dataset without changing the normal pattern materially.
            if index < len(FAILURE_REASON_CODES):
                primary = FAILURE_REASON_CODES[index]
            reasons.append({
                "outcome_id": outcome_id,
                "reason_code": primary,
                "is_primary": True,
                "user_confirmed": True,
                "created_at": (recorded_at + timedelta(minutes=2)).isoformat(),
            })
            if signals.get("interruption", -1) > 1.0 and primary != "interruption":
                reasons.append({
                    "outcome_id": outcome_id,
                    "reason_code": "interruption",
                    "is_primary": False,
                    "user_confirmed": True,
                    "created_at": (recorded_at + timedelta(minutes=3)).isoformat(),
                })

    return pd.DataFrame(plans), pd.DataFrame(outcomes), pd.DataFrame(reasons)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=800)
    parser.add_argument("--seed", type=int, default=20260810)
    parser.add_argument("--outdir", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    if args.rows < 100:
        raise SystemExit("use at least 100 rows for a useful baseline")
    plans, outcomes, reasons = generate(args.rows, args.seed)
    args.outdir.mkdir(parents=True, exist_ok=True)
    plans.to_csv(args.outdir / "synthetic_plans.csv", index=False)
    outcomes.to_csv(args.outdir / "synthetic_outcomes.csv", index=False)
    reasons.to_csv(args.outdir / "synthetic_failure_reasons.csv", index=False)
    metadata = {
        "synthetic": True,
        "rows_requested": args.rows,
        "seed": args.seed,
        "warning": "Development baseline only; do not report as human or production data.",
    }
    (args.outdir / "synthetic_manifest.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {len(plans)} plans, {len(outcomes)} outcomes, {len(reasons)} confirmed reasons")


if __name__ == "__main__":
    main()
