from __future__ import annotations

import asyncio
import json
from datetime import date, datetime, timezone

from app.schemas.coach_tools import ToolCall, ToolDecision
from app.services.chat_service import ChatService
from app.services.coach_tool_registry import CoachToolRegistry
from app.services.coaching_context_service import CoachingContextService
from app.services.llm_client import LLMProviderError


class _Result:
    def __init__(self, data):
        self.data = data


class _ReadQuery:
    def __init__(self, db, table_name):
        self.db = db
        self.table_name = table_name
        self.filters = []
        self.row_limit = None

    def select(self, _columns):
        return self

    def eq(self, field, value):
        self.filters.append(("eq", field, value))
        return self

    def gte(self, field, value):
        self.filters.append(("gte", field, value))
        return self

    def lte(self, field, value):
        self.filters.append(("lte", field, value))
        return self

    def in_(self, field, values):
        self.filters.append(("in", field, values))
        return self

    def limit(self, value):
        self.row_limit = value
        return self

    def execute(self):
        self.db.reads.append((self.table_name, list(self.filters)))
        rows = list(self.db.tables.get(self.table_name, []))
        for operation, field, value in self.filters:
            if operation == "eq":
                rows = [row for row in rows if row.get(field) == value]
            elif operation == "gte":
                rows = [row for row in rows if str(row.get(field) or "") >= str(value)]
            elif operation == "lte":
                rows = [row for row in rows if str(row.get(field) or "") <= str(value)]
            elif operation == "in":
                rows = [row for row in rows if str(row.get(field)) in {str(v) for v in value}]
        if self.row_limit is not None:
            rows = rows[: self.row_limit]
        return _Result(rows)

    def __getattr__(self, name):
        if name in {"insert", "update", "upsert", "delete"}:
            raise AssertionError(f"read-only tool attempted {name}")
        raise AttributeError(name)


class _ReadOnlyDB:
    def __init__(self, tables):
        self.tables = tables
        self.reads = []

    def table(self, name):
        return _ReadQuery(self, name)


class _PreferenceQuery(_ReadQuery):
    def __init__(self, db, table_name):
        super().__init__(db, table_name)
        self.payload = None

    def upsert(self, payload, on_conflict):
        self.payload = payload
        self.db.writes.append((self.table_name, payload, on_conflict))
        return self

    def execute(self):
        if self.payload is not None:
            return _Result([self.payload])
        return super().execute()


class _PreferenceDB(_ReadOnlyDB):
    def __init__(self):
        super().__init__({"user_coaching_preferences": []})
        self.writes = []

    def table(self, name):
        return _PreferenceQuery(self, name)


class _ToolSelectingLLM:
    def __init__(self, decision):
        self.decision = decision
        self.selection_messages = []
        self.final_messages = []

    async def select_tools(self, system_prompt, messages, tools):
        self.selection_messages = messages
        self.tools = tools
        return self.decision

    async def stream_coaching_response(self, messages):
        self.final_messages = messages
        yield "A compatible streamed response."


class _NeverReadContext:
    def __getattribute__(self, name):
        if name.startswith("get_"):
            raise AssertionError("a HabitTrace data tool should not have executed")
        return object.__getattribute__(self, name)


class _PlanningLLM:
    def __init__(self):
        self.tool_selection_called = False

    async def select_tools(self, system_prompt, messages, tools):
        self.tool_selection_called = True
        raise LLMProviderError("selector unavailable")


class _PlanningContext:
    def build(self, user_id, timezone_name, through_date):
        return {
            "preferences": {
                "timezone_name": timezone_name,
                "preferred_day_start": "08:00",
                "preferred_day_end": "22:00",
                "minimum_buffer_minutes": 0,
            },
            "last_30_days": {"success_rate": None},
            "hour_patterns": [],
            "category_patterns": [],
            "upcoming_schedule": [],
        }


class _ProposalRepository:
    def __init__(self):
        self.proposals = []

    def create_proposal(self, user_id, conversation_id, payload):
        self.proposals.append(payload)
        return {"id": "proposal-1"}

    def add_message(self, conversation_id, user_id, role, content):
        return None


def _event_payloads(events: list[str]) -> list[dict]:
    payloads = []
    for event in events:
        raw = event.removeprefix("data: ").strip()
        if raw != "[DONE]":
            payloads.append(json.loads(raw))
    return payloads


def test_basic_conversation_can_select_zero_tools_and_keeps_sse_contract() -> None:
    service = ChatService(None)
    service.tool_registry = CoachToolRegistry(_NeverReadContext())
    llm = _ToolSelectingLLM(ToolDecision())
    service.llm = llm

    async def collect() -> list[str]:
        return [event async for event in service.stream("user-1", "Hey, good to see you!", [])]

    events = asyncio.run(collect())
    payloads = _event_payloads(events)

    assert payloads == [{"token": "A compatible streamed response."}]
    assert events[-1] == "data: [DONE]\n\n"
    assert len(llm.tools) == 6
    assert '"tool_results": []' in llm.final_messages[0]["content"]


def test_semantic_study_question_executes_only_scoped_selected_tools() -> None:
    today = date.today().isoformat()
    now = datetime.now(timezone.utc).isoformat()
    db = _ReadOnlyDB(
        {
            "tasks": [
                {
                    "id": "study-1",
                    "user_id": "trusted-user",
                    "title": "Read algorithms chapter",
                    "task_category": "Study",
                    "task_status": "failed",
                    "planned_date": today,
                    "planned_start_time": "19:00",
                    "planned_duration_min": 90,
                },
                {
                    "id": "work-1",
                    "user_id": "trusted-user",
                    "title": "Write report",
                    "task_category": "Work",
                    "task_status": "success",
                    "planned_date": today,
                    "planned_start_time": "09:00",
                    "planned_duration_min": 30,
                },
            ],
            "executions": [
                {
                    "user_id": "trusted-user",
                    "task_id": "study-1",
                    "task_status": "failed",
                    "failure_reason": "interruptions",
                    "interruption_count": 4,
                    "created_at": now,
                }
            ],
        }
    )
    service = ChatService(None)
    service.tool_registry = CoachToolRegistry(CoachingContextService(db))
    service.llm = _ToolSelectingLLM(
        ToolDecision(
            calls=[
                ToolCall(name="get_task_performance", arguments={"category": "Study"}),
                ToolCall(name="get_failure_patterns", arguments={"category": "Study"}),
            ]
        )
    )

    async def collect() -> list[str]:
        return [
            event
            async for event in service.stream(
                "trusted-user",
                "It feels as though learning sessions always fall apart. What is going on?",
                [{"role": "assistant", "content": "You said this was about studying."}],
            )
        ]

    asyncio.run(collect())
    prompt = service.llm.final_messages[0]["content"]

    assert '"category": "Study"' in prompt
    assert '"failure_reasons": [{"reason": "interruptions", "count": 1}]' in prompt
    assert '"successful_tasks": 0' in prompt
    assert '"category": "Work"' not in prompt
    assert all(
        ("eq", "user_id", "trusted-user") in filters for _table, filters in db.reads
    )


def test_tool_arguments_are_validated_and_user_id_cannot_be_overridden() -> None:
    db = _ReadOnlyDB({})
    registry = CoachToolRegistry(CoachingContextService(db))

    invalid_period = registry.execute(
        ToolCall(name="get_task_performance", arguments={"period_days": 1000}),
        user_id="trusted-user",
        timezone_name="UTC",
    )
    injected_user = registry.execute(
        ToolCall(
            name="get_task_performance",
            arguments={"period_days": 30, "user_id": "attacker"},
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )

    assert invalid_period.ok is False
    assert injected_user.ok is False
    assert db.reads == []


def test_unknown_and_malformed_tool_calls_fail_safely() -> None:
    db = _ReadOnlyDB({})
    registry = CoachToolRegistry(CoachingContextService(db))

    unknown = registry.execute(
        ToolCall(name="delete_everything", arguments={}),
        user_id="trusted-user",
        timezone_name="UTC",
    )
    malformed = registry.execute(
        ToolCall(
            name="get_schedule",
            arguments={"start_date": "not-a-date", "end_date": "also-not-a-date"},
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )

    assert unknown.ok is False
    assert malformed.ok is False
    assert {tool.name for tool in registry.definitions()} == {
        "get_task_performance",
        "get_failure_patterns",
        "get_schedule",
        "get_user_preferences",
        "find_available_times",
        "save_user_preferences",
    }
    assert db.reads == []


def test_read_tools_remain_non_mutating() -> None:
    db = _ReadOnlyDB({"tasks": [], "executions": [], "user_coaching_preferences": []})
    registry = CoachToolRegistry(CoachingContextService(db))

    calls = [
        ToolCall(name="get_task_performance", arguments={}),
        ToolCall(name="get_failure_patterns", arguments={}),
        ToolCall(
            name="get_schedule",
            arguments={"start_date": date.today(), "end_date": date.today()},
        ),
        ToolCall(name="get_user_preferences", arguments={}),
    ]
    results = registry.execute_many(calls, user_id="trusted-user", timezone_name="UTC")

    assert all(result.ok for result in results)
    assert all(tool.kind == "read" for tool in registry.definitions() if tool.name in {
        "get_task_performance", "get_failure_patterns", "get_schedule", "get_user_preferences"
    })


def test_existing_planning_parser_is_a_selector_failure_fallback() -> None:
    service = ChatService(None)
    service.llm = _PlanningLLM()
    service.context_service = _PlanningContext()
    service.repository = _ProposalRepository()
    service.tool_registry = CoachToolRegistry(service.context_service)
    service._open_conversation = lambda _user, _conversation: (None, [])

    async def collect() -> list[str]:
        return [
            event
            async for event in service.stream(
                "trusted-user",
                "Please schedule a study review tomorrow at 10 AM.",
                [],
                timezone_name="America/Denver",
            )
        ]

    events = asyncio.run(collect())
    payloads = _event_payloads(events)

    assert service.llm.tool_selection_called is True
    assert service.repository.proposals
    assert any(payload.get("proposal", {}).get("id") == "proposal-1" for payload in payloads)
    assert events[-1] == "data: [DONE]\n\n"


def test_preference_mutation_uses_validated_existing_storage_with_server_identity() -> None:
    db = _PreferenceDB()
    registry = CoachToolRegistry(CoachingContextService(db))

    result = registry.execute(
        ToolCall(
            name="save_user_preferences",
            arguments={"minimum_buffer_minutes": 15, "preferred_day_start": "09:00"},
        ),
        user_id="authenticated-user",
        timezone_name="America/Denver",
    )

    assert result.ok is True
    assert result.data == {
        "saved_preferences": {
            "preferred_day_start": "09:00",
            "minimum_buffer_minutes": 15,
        }
    }
    assert len(db.writes) == 1
    table, payload, conflict = db.writes[0]
    assert table == "user_coaching_preferences"
    assert conflict == "user_id"
    assert payload["user_id"] == "authenticated-user"
    assert payload["timezone_name"] == "America/Denver"
    assert "user_id" not in result.data["saved_preferences"]


def test_unsafe_or_malformed_preference_mutations_fail_closed() -> None:
    db = _PreferenceDB()
    registry = CoachToolRegistry(CoachingContextService(db))

    results = [
        registry.execute(
            ToolCall(name="save_user_preferences", arguments={}),
            user_id="authenticated-user",
            timezone_name="UTC",
        ),
        registry.execute(
            ToolCall(name="save_user_preferences", arguments={"session_minutes": 25}),
            user_id="authenticated-user",
            timezone_name="UTC",
        ),
        registry.execute(
            ToolCall(name="save_user_preferences", arguments={"preferred_day_start": "9 AM"}),
            user_id="authenticated-user",
            timezone_name="UTC",
        ),
        registry.execute(
            ToolCall(name="save_user_preferences", arguments={"minimum_buffer_minutes": -1}),
            user_id="authenticated-user",
            timezone_name="UTC",
        ),
        registry.execute(
            ToolCall(
                name="save_user_preferences",
                arguments={"minimum_buffer_minutes": 10, "user_id": "attacker"},
            ),
            user_id="authenticated-user",
            timezone_name="UTC",
        ),
    ]

    assert all(result.ok is False for result in results)
    assert db.writes == []


def test_explicit_preference_request_streams_natural_acknowledgement_without_proposal() -> None:
    db = _PreferenceDB()
    service = ChatService(None)
    service.tool_registry = CoachToolRegistry(CoachingContextService(db))
    service.llm = _ToolSelectingLLM(
        ToolDecision(
            calls=[
                ToolCall(
                    name="save_user_preferences",
                    arguments={"minimum_buffer_minutes": 15},
                )
            ]
        )
    )

    async def collect() -> list[str]:
        return [
            event
            async for event in service.stream(
                "authenticated-user",
                "Please remember that I need a buffer between tasks.",
                [],
            )
        ]

    payloads = _event_payloads(asyncio.run(collect()))

    assert db.writes
    assert payloads == [{"token": "A compatible streamed response."}]
    assert '"saved_preferences": {"minimum_buffer_minutes": 15}' in (
        service.llm.final_messages[0]["content"]
    )
    assert all("proposal" not in payload for payload in payloads)


def test_casual_preference_observation_selects_no_write() -> None:
    db = _PreferenceDB()
    service = ChatService(None)
    service.tool_registry = CoachToolRegistry(CoachingContextService(db))
    service.llm = _ToolSelectingLLM(ToolDecision())

    async def collect() -> list[str]:
        return [
            event
            async for event in service.stream(
                "authenticated-user", "I hate waking up early.", []
            )
        ]

    asyncio.run(collect())

    assert db.writes == []
    assert "casual observation" in service._tool_selection_prompt("UTC")


def test_preference_mutation_can_coexist_with_a_read_capability() -> None:
    db = _PreferenceDB()
    registry = CoachToolRegistry(CoachingContextService(db))

    results = registry.execute_many(
        [
            ToolCall(name="get_user_preferences", arguments={}),
            ToolCall(
                name="save_user_preferences",
                arguments={"coaching_style": "direct"},
            ),
        ],
        user_id="authenticated-user",
        timezone_name="UTC",
    )

    assert [result.name for result in results] == [
        "get_user_preferences",
        "save_user_preferences",
    ]
    assert all(result.ok for result in results)
    definition = next(
        tool for tool in registry.definitions() if tool.name == "save_user_preferences"
    )
    assert definition.kind == "mutation"
