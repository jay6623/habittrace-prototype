"""Transparent, non-model explanations for plan-time AI predictions."""

from __future__ import annotations

from typing import Any


def build_plan_explanation(plan: dict[str, Any], result: dict[str, Any]) -> dict[str, Any]:
    """Return actionable signals without claiming model feature attribution."""

    factors: list[dict[str, Any]] = []
    actions: list[dict[str, str]] = []

    required_energy = _number(plan.get("required_energy"))
    current_energy = _number(plan.get("current_energy"))
    if required_energy is not None and current_energy is not None:
        gap = required_energy - current_energy
        if gap > 0:
            factors.append(
                {
                    "feature": "energy_gap",
                    "direction": "negative",
                    "value": gap,
                    "message": "The task requires more energy than currently available.",
                }
            )
            actions.append(
                {
                    "code": "reduce_scope",
                    "title": "Reduce the first step",
                    "detail": "Start with a smaller milestone or shorten the first work block.",
                }
            )
        elif gap <= 0:
            factors.append(
                {
                    "feature": "energy_gap",
                    "direction": "positive",
                    "value": gap,
                    "message": "Current energy meets the task requirement.",
                }
            )

    required_focus = _number(plan.get("required_focus"))
    current_focus = _number(plan.get("current_focus"))
    if required_focus is not None and current_focus is not None:
        gap = required_focus - current_focus
        if gap > 0:
            factors.append(
                {
                    "feature": "focus_gap",
                    "direction": "negative",
                    "value": gap,
                    "message": "The task requires more focus than currently available.",
                }
            )
            actions.append(
                {
                    "code": "remove_distractions",
                    "title": "Protect a focus block",
                    "detail": "Silence notifications and define one concrete starting action.",
                }
            )
        else:
            factors.append(
                {
                    "feature": "focus_gap",
                    "direction": "positive",
                    "value": gap,
                    "message": "Current focus meets the task requirement.",
                }
            )

    duration = _number(plan.get("planned_duration_minutes"))
    if duration is not None and duration > 90:
        factors.append(
            {
                "feature": "planned_duration_minutes",
                "direction": "negative",
                "value": duration,
                "message": "A long uninterrupted block may be harder to complete.",
            }
        )
        actions.append(
            {
                "code": "split_task",
                "title": "Split the task",
                "detail": "Use two shorter blocks with a planned break between them.",
            }
        )

    daily_minutes = _number(plan.get("daily_planned_minutes"))
    if daily_minutes is not None and daily_minutes > 360:
        factors.append(
            {
                "feature": "daily_planned_minutes",
                "direction": "negative",
                "value": daily_minutes,
                "message": "The surrounding daily schedule is already dense.",
            }
        )
        actions.append(
            {
                "code": "reschedule",
                "title": "Use a lower-load time",
                "detail": "Try the time recommendation to find a less overloaded slot.",
            }
        )

    reason = result.get("predicted_failure_reason")
    reason_actions = {
        "interruption": {
            "code": "protect_time",
            "title": "Protect the block",
            "detail": "Plan a distraction-free block and add a small buffer.",
        },
        "underestimated_time": {
            "code": "add_buffer",
            "title": "Add time buffer",
            "detail": "Increase the estimate or split the task into smaller parts.",
        },
        "unclear_plan": {
            "code": "define_first_step",
            "title": "Define the first step",
            "detail": "Write the smallest observable action before starting.",
        },
        "schedule_overload": {
            "code": "reduce_load",
            "title": "Reduce surrounding load",
            "detail": "Move or remove one nearby task before starting this one.",
        },
    }
    if reason in reason_actions:
        actions.insert(0, reason_actions[reason])

    unique_actions = list({item["code"]: item for item in actions}.values())
    return {
        "source": "heuristic_plan_signals",
        "factors": factors[:6],
        "recommended_actions": unique_actions[:4],
    }


def _number(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
