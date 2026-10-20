from __future__ import annotations

import asyncio
from datetime import date, timedelta

import pytest
from pydantic import ValidationError

from app.schemas.coach_chart import CoachChartSpec
from app.schemas.coach_tools import ToolCall, ToolDecision
from app.services.chat_service import ChatService
from app.services.coach_repository import CoachRepository
from app.services.coach_tool_registry import CoachToolRegistry
from app.services.coaching_context_service import CoachingContextService
from app.services.coaching_visualization_service import CoachingVisualizationService

from .test_coach_tools import (
    _event_payloads,
    _ReadOnlyDB,
    _ReadQuery,
    _ToolSelectingLLM,
)


def _tasks():
    today = date.today()
    rows = []
    for days, hour in [(0, "09:00"), (8, "19:00")]:
        for index in range(5):
            rows.append(
                {
                    "id": f"{days}-{index}",
                    "user_id": "owner",
                    "title": "Study",
                    "planned_date": (today - timedelta(days=days)).isoformat(),
                    "planned_start_time": hour,
                    "task_status": "success" if index < (4 if days == 0 else 2) else "failed",
                }
            )
    return rows


def _registry(rows=None):
    db = _ReadOnlyDB({"tasks": _tasks() if rows is None else rows})
    return CoachToolRegistry(CoachingContextService(db)), db


def _execute(registry, arguments=None, user="owner", focus=None):
    return registry.execute(
        ToolCall(name="get_task_performance", arguments=arguments or {}),
        user_id=user,
        timezone_name="UTC",
        visualization_focus=focus,
    )


@pytest.mark.parametrize("group,axis", [("hour", "Planned hour (local)"), ("weekday", "Weekday")])
def test_actual_group_rates_and_samples(group, axis):
    registry, _ = _registry()
    result = _execute(registry, {"group_by": [group]})
    assert result.ok and result.chart
    chart = result.chart
    assert chart.chart_type == "bar" and chart.x_axis == axis
    assert sorted(p.value for p in chart.data) == [40, 80]
    assert chart.sample_size == 10
    assert all(p.sample_size == 5 for p in chart.data)
    assert "chart" not in result.model_dump()  # no chart payload sent back into the LLM


def test_weekly_trend_excludes_pending_missing_and_other_users():
    rows = _tasks() + [
        {**_tasks()[0], "task_status": "pending"},
        {**_tasks()[0], "user_id": "other", "task_status": "success"},
    ]
    registry, db = _registry(rows)
    result = _execute(registry)
    assert result.chart.chart_type == "line"
    assert result.chart.interval_days == 7
    assert [p.value for p in result.chart.data] == [40, 80]
    assert result.chart.sample_size == 10
    assert all(("eq", "user_id", "owner") in filters for _, filters in db.reads)
    assert _execute(registry, user="nobody").chart is None


def test_missing_or_invalid_times_are_not_assigned_to_noon():
    registry, _ = _registry(
        _tasks()
        + [{**_tasks()[0], "planned_start_time": value} for value in [None, "", "bad", "25:00"]]
    )
    result = _execute(registry, {"group_by": ["hour"]})
    assert [p.label for p in result.chart.data] == ["09:00", "19:00"]
    assert result.chart.sample_size == 10


@pytest.mark.parametrize("rows", [[], _tasks()[:4], _tasks()[:5], _tasks() * 20])
def test_insufficient_or_truncated_data_has_no_chart(rows):
    registry, _ = _registry(rows)
    assert _execute(registry).chart is None


def test_title_filter_cannot_hide_a_truncated_query():
    registry, _ = _registry(_tasks() + [{**_tasks()[0], "title": "Other"}] * 190)
    result = _execute(registry, {"title_query": "Study"})
    assert result.data["current"]["sample_size"] == 10
    assert result.data["truncated"]
    assert result.chart is None


def test_weekly_fallback_aggregates_sparse_days():
    today = date.today()
    rows = [
        {**_tasks()[0], "planned_date": (today - timedelta(days=day)).isoformat()}
        for day in range(28)
    ]
    registry, _ = _registry(rows)
    chart = _execute(registry).chart
    assert chart and chart.interval_days == 7
    assert all(p.value == 100 and p.sample_size >= 1 for p in chart.data)
    assert chart.sample_size == 28
    assert "uncertain" in chart.note


def test_comparison_uses_actual_previous_and_current_period_totals():
    previous_day = (date.today() - timedelta(days=31)).isoformat()
    registry, _ = _registry(
        _tasks()
        + [{**task, "planned_date": previous_day, "task_status": "failed"} for task in _tasks()[:5]]
    )
    chart = _execute(registry, {"compare_previous_period": True}).chart
    assert chart and chart.chart_type == "bar" and chart.x_axis == "Recorded period"
    assert chart.focus == "comparison" and chart.interval_days is None
    assert [point.value for point in chart.data] == [0, 60]
    assert [point.completed for point in chart.data] == [0, 6]
    assert chart.sample_size == 15


def test_failure_counts_only_from_recorded_reasons():
    registry, db = _registry()
    db.tables["executions"] = [
        {
            "task_id": "0-0",
            "user_id": "owner",
            "task_status": "failed",
            "failure_reason": reason,
            "created_at": date.today().isoformat(),
        }
        for reason in ["distraction", "distraction", "distraction", "tired", "tired", None]
    ]
    result = registry.execute(
        ToolCall(name="get_failure_patterns"), user_id="owner", timezone_name="UTC"
    )
    assert result.chart.units == "count"
    assert [p.value for p in result.chart.data] == [3, 2]
    assert result.chart.sample_size == 5
    assert result.data["failed_executions"] == 6


def test_visualization_failure_does_not_lose_tool_result(monkeypatch):
    registry, _ = _registry()

    def fail(*_args, **_kwargs):
        raise ValueError("bad chart")

    monkeypatch.setattr(CoachingVisualizationService, "build", fail)
    result = _execute(registry)
    assert result.ok and result.data["current"]["sample_size"] == 10
    assert result.chart is None


class _MemoryQuery(_ReadQuery):
    def insert(self, payload):
        self.db.tables.setdefault(self.table_name, []).append({"id": "message", **payload})
        return self

    def update(self, _payload):
        return self

    def order(self, *_args, **_kwargs):
        return self


class _MemoryDB(_ReadOnlyDB):
    def table(self, name):
        return _MemoryQuery(self, name)


@pytest.mark.parametrize("native", [False, True])
def test_both_stream_paths_emit_one_chart_and_persist_on_correct_message(native):
    service = ChatService(None)
    service.tool_registry, _ = _registry()
    call = ToolCall(name="get_task_performance", arguments={"group_by": ["hour"]})
    llm = _ToolSelectingLLM(ToolDecision(calls=[call, call], visualization_focus="hour"))
    if native:

        async def stream(_messages, _definitions, execute):
            execute([call, call])
            yield "A compatible streamed response."

        llm.stream_coaching_response_with_tools = stream
    service.llm = llm
    db = _MemoryDB({"coach_messages": [], "coach_conversations": []})
    service.repository = CoachRepository(db)
    service._open_conversation = lambda *_: ({"id": "conversation"}, [])

    async def collect():
        return [event async for event in service.stream("owner", "When am I productive?", [])]

    events = asyncio.run(collect())
    payloads = _event_payloads(events)
    charts = [p["chart"] for p in payloads if "chart" in p]
    assert len(charts) == 1
    assert {"token": "A compatible streamed response."} in payloads
    assert events[-1] == "data: [DONE]\n\n"
    restored = service.repository.list_messages("conversation", "owner")
    assistant = next(row for row in restored if row["role"] == "assistant")
    assert assistant["metadata"]["chart"] == charts[0]
    assert assistant["conversation_id"] == "conversation"
    assert service.repository.list_messages("conversation", "other") == []


@pytest.mark.parametrize(
    "message", ["Thank you", "Help me stay motivated", "I'm feeling unmotivated"]
)
def test_normal_conversation_has_no_chart(message):
    service = ChatService(None)
    service.tool_registry, db = _registry()
    service.llm = _ToolSelectingLLM(ToolDecision())

    async def collect():
        return [event async for event in service.stream("owner", message, [])]

    assert not any("chart" in p for p in _event_payloads(asyncio.run(collect())))
    assert db.reads == []


def test_chart_schema_rejects_invalid_statistics():
    registry, _ = _registry()
    chart = _execute(registry).chart.model_dump(mode="json")
    chart["data"][0]["value"] = 101
    with pytest.raises(ValidationError):
        CoachChartSpec.model_validate(chart)


def test_legacy_messages_round_trip_without_metadata():
    db = _MemoryDB({"coach_messages": [], "coach_conversations": []})
    repo = CoachRepository(db)
    repo.add_message("conversation", "owner", "assistant", "Legacy text")
    assert repo.list_messages("conversation", "owner")[0]["content"] == "Legacy text"


def test_chart_routes_require_authentication(client):
    assert client.post("/chat", json={"message": "How am I doing?"}).status_code == 401
    assert client.get("/chat/conversations/latest").status_code == 401


def test_identity_cannot_be_supplied_in_tool_arguments():
    registry, db = _registry()
    result = _execute(registry, {"user_id": "other"})
    assert not result.ok and result.chart is None and db.reads == []


def test_failed_stream_never_emits_or_persists_chart():
    from app.services.llm_client import LLMProviderError

    service = ChatService(None)
    service.tool_registry, _ = _registry()
    service.llm = _ToolSelectingLLM(ToolDecision(calls=[ToolCall(name="get_task_performance")]))

    async def stream(_messages):
        yield "Partial text"
        raise LLMProviderError("provider unavailable")

    service.llm.stream_coaching_response = stream

    async def collect():
        return [event async for event in service.stream("owner", "Am I improving?", [])]

    events = _event_payloads(asyncio.run(collect()))
    assert any("error" in event for event in events)
    assert not any("chart" in event for event in events)


def _live_trend_tasks():
    rows = []
    for week, successful, total in [
        ("2026-08-31", 0, 2),
        ("2026-09-07", 5, 7),
        ("2026-09-14", 1, 2),
        ("2026-09-28", 4, 4),
        ("2026-10-05", 1, 2),
    ]:
        for index in range(total):
            rows.append(
                {
                    "id": f"{week}-{index}",
                    "user_id": "owner",
                    "title": "Study",
                    "planned_date": (date.fromisoformat(week) + timedelta(days=index)).isoformat(),
                    "planned_start_time": None,
                    "task_status": "success" if index < successful else "failed",
                }
            )
    return rows


@pytest.mark.parametrize("native", [False, True])
@pytest.mark.parametrize(
    "focus,question",
    [
        ("trend", "How has my habit completion rate changed over the last 60 days?"),
        ("comparison", "Compare my last 60 days with the preceding 60 days."),
        ("hour", "When am I most productive?"),
    ],
)
def test_live_questions_keep_weekly_trend_and_suppress_unrelated_chart(
    monkeypatch,
    native,
    focus,
    question,
):
    monkeypatch.setattr(
        CoachingContextService, "_today", staticmethod(lambda _: date(2026, 10, 19))
    )
    service = ChatService(None)
    service.tool_registry, _ = _registry(
        _live_trend_tasks()
        + [{**task, "planned_date": "2026-08-01", "task_status": "failed"} for task in _tasks()[:5]]
    )
    calls = [
        ToolCall(
            name="get_task_performance",
            arguments={
                "period_days": 60,
                "compare_previous_period": True,
            },
        ),
        ToolCall(name="get_task_performance", arguments={"period_days": 60, "group_by": ["hour"]}),
    ]

    class LLM(_ToolSelectingLLM):
        selection_count = 0

        async def select_tools(self, *args):
            self.selection_count += 1
            return await super().select_tools(*args)

    llm = LLM(ToolDecision(calls=calls, visualization_focus=focus))
    if native:

        async def stream(_messages, _definitions, execute):
            results = execute(calls)
            assert results[0].data["current"]["sample_size"] == 17
            assert results[0].data["current"]["success_rate"] == 64.7
            assert results[0].data["previous"]["sample_size"] == 5
            assert results[1].data["by_hour"] == []
            yield (
                "Recorded weekly results." if focus == "trend" else "Insufficient time-of-day data."
            )

        llm.stream_coaching_response_with_tools = stream
    service.llm = llm
    db = _MemoryDB({"coach_messages": [], "coach_conversations": []})
    service.repository = CoachRepository(db)
    service._open_conversation = lambda *_: ({"id": "conversation"}, [])

    async def collect():
        return [event async for event in service.stream("owner", question, [])]

    events = asyncio.run(collect())
    charts = [p["chart"] for p in _event_payloads(events) if "chart" in p]
    saved = next(row for row in db.tables["coach_messages"] if row["role"] == "assistant")
    assert llm.selection_count == (1 if native else 2)  # existing calls only
    assert events[-1] == "data: [DONE]\n\n"
    if focus == "hour":
        assert charts == [] and "metadata" not in saved
    elif focus == "comparison":
        assert len(charts) == 1
        chart = CoachChartSpec.model_validate(charts[0])
        assert chart.chart_type == "bar" and chart.focus == "comparison"
        assert chart.interval_days is None and chart.sample_size == 22
        assert [p.value for p in chart.data] == [0, 64.7]
        assert [p.completed for p in chart.data] == [0, 11]
        assert [p.sample_size for p in chart.data] == [5, 17]
        assert chart.period.start == date(2026, 6, 22)
        assert chart.period.end == date(2026, 10, 19)
        assert saved["metadata"]["chart"] == charts[0]
    else:
        assert len(charts) == 1
        chart = CoachChartSpec.model_validate(charts[0])
        assert chart.chart_type == "line" and chart.interval_days == 7
        assert chart.focus == "trend" and chart.sample_size == 17
        assert chart.period.start == date(2026, 8, 21)
        assert chart.period.end == date(2026, 10, 19)
        assert [p.value for p in chart.data] == [0, 71.4, 50, 100, 50]
        assert [p.completed for p in chart.data] == [0, 5, 1, 4, 1]
        assert [p.sample_size for p in chart.data] == [2, 7, 2, 4, 2]
        assert [p.label for p in chart.data] == [
            "2026-08-31",
            "2026-09-07",
            "2026-09-14",
            "2026-09-28",
            "2026-10-05",
        ]
        assert saved["metadata"]["chart"] == charts[0]


@pytest.mark.parametrize("invalid", ["truncated", "rate", "missing_week", "duplicate", "counts"])
def test_small_weekly_samples_still_reject_unreliable_series(monkeypatch, invalid):
    monkeypatch.setattr(
        CoachingContextService, "_today", staticmethod(lambda _: date(2026, 10, 19))
    )
    registry, _ = _registry(_live_trend_tasks())
    result = _execute(registry, {"period_days": 60}).data
    if invalid == "truncated":
        result["truncated"] = True
    elif invalid == "rate":
        result["by_week"][1]["success_rate"] = 99
    elif invalid == "missing_week":
        result["by_week"].pop()
    elif invalid == "duplicate":
        result["by_week"][1]["date"] = result["by_week"][0]["date"]
    else:
        result["by_week"][1]["successful_tasks"] += 1
    from app.schemas.coach_tools import GetTaskPerformanceArgs

    assert (
        CoachingVisualizationService().build(
            "get_task_performance",
            GetTaskPerformanceArgs(period_days=60),
            result,
        )
        is None
    )


def test_unspecified_visualization_focus_fails_closed():
    service = ChatService(None)
    service.tool_registry, _ = _registry()
    service.llm = _ToolSelectingLLM(ToolDecision(calls=[ToolCall(name="get_task_performance")]))

    async def collect():
        return [event async for event in service.stream("owner", "When am I most productive?", [])]

    assert not any("chart" in p for p in _event_payloads(asyncio.run(collect())))


def test_comparison_with_insufficient_previous_outcomes_never_substitutes_a_trend():
    previous_day = (date.today() - timedelta(days=31)).isoformat()
    registry, _ = _registry(
        _tasks() + [{**task, "planned_date": previous_day} for task in _tasks()[:4]]
    )
    assert _execute(registry, {"compare_previous_period": True}, focus="comparison").chart is None
    trend = _execute(registry, {"compare_previous_period": True}, focus="trend").chart
    assert trend and trend.interval_days == 7 and trend.sample_size == 10


def test_trend_with_one_calendar_week_omits_chart_even_with_valid_period_comparison():
    # Two well-populated days in one week must not become a weekly trend or aggregate line.
    monday = date.today() - timedelta(days=date.today().weekday())
    rows = [{**task, "planned_date": monday.isoformat()} for task in _tasks()]
    rows += [
        {**task, "planned_date": (monday - timedelta(days=31)).isoformat()} for task in _tasks()
    ]
    registry, _ = _registry(rows)
    assert _execute(registry, {"compare_previous_period": True}, focus="trend").chart is None


@pytest.mark.parametrize("bad_field,bad_value", [("completed", 99), ("completed", 1)])
def test_schema_rejects_inconsistent_completed_counts(bad_field, bad_value):
    registry, _ = _registry()
    chart = _execute(registry).chart.model_dump(mode="json")
    chart["data"][0][bad_field] = bad_value
    with pytest.raises(ValidationError):
        CoachChartSpec.model_validate(chart)


def test_schema_cannot_label_period_totals_as_a_trend_line():
    registry, _ = _registry()
    chart = _execute(registry).chart.model_dump(mode="json")
    chart.update(chart_type="line", focus="comparison", interval_days=None)
    with pytest.raises(ValidationError):
        CoachChartSpec.model_validate(chart)


def test_coach_prompts_distinguish_weekly_trends_from_period_comparisons():
    prompt = ChatService._tool_selection_prompt("UTC")
    assert "comparison" in prompt and "never a line between period totals" in prompt
    response_prompt = ChatService._coach_system_prompt({"visualization_focus": "trend"}, "UTC")
    assert "calendar-week completion rates from by_week" in response_prompt
    assert '"visualization_focus": "trend"' in response_prompt
