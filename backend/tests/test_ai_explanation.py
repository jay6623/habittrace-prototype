from app.services.ai_explanation import build_plan_explanation


def test_explanation_returns_actionable_signals_for_overloaded_plan() -> None:
    result = build_plan_explanation(
        {
            "required_energy": 4,
            "current_energy": 2,
            "required_focus": 4,
            "current_focus": 3,
            "planned_duration_minutes": 120,
            "daily_planned_minutes": 420,
        },
        {"predicted_failure_reason": "interruption"},
    )

    assert result["source"] == "heuristic_plan_signals"
    assert len(result["factors"]) >= 3
    action_codes = {action["code"] for action in result["recommended_actions"]}
    assert "reduce_scope" in action_codes
    assert "protect_time" in action_codes
