from __future__ import annotations

import asyncio
import json
from datetime import date, datetime, timedelta, timezone
from uuid import UUID

import app.routes.chat as chat_route
from app.schemas.chat import ProposalConfirmRequest
from app.schemas.coach_tools import FindAvailableTimesArgs, ToolCall, ToolDecision
from app.services.chat_service import ChatService
from app.services.coach_tool_registry import CoachToolRegistry
from app.services.coaching_planning_service import CoachingPlanningService
from app.services.coaching_recommendation_service import CoachingRecommendationService


class _PlanningContext:
    def __init__(self, scheduled=None):
        self.scheduled = scheduled or []
        self.calls = []

    def get_schedule(self, user_id, *, start_date, end_date):
        self.calls.append(("schedule", user_id, start_date, end_date))
        return {"tasks": self.scheduled, "result_count": len(self.scheduled)}

    def get_preferences(self, user_id, timezone_name):
        self.calls.append(("preferences", user_id, timezone_name))
        return {
            "timezone_name": timezone_name,
            "preferred_day_start": "08:00",
            "preferred_day_end": "12:00",
            "minimum_buffer_minutes": 0,
        }

    def get_task_performance(self, user_id, **kwargs):
        self.calls.append(("performance", user_id, kwargs))
        return {
            "current": {"success_rate": 60.0, "sample_size": 10},
            "by_hour": [],
        }

    def get_failure_patterns(self, user_id, **kwargs):
        self.calls.append(("failures", user_id, kwargs))
        return {"failure_reasons": []}


class _ProposalRepository:
    def __init__(self):
        self.proposals = []

    def create_proposal(self, user_id, conversation_id, payload):
        self.proposals.append((user_id, conversation_id, payload))
        return {"id": "proposal-42"}

    def add_message(self, conversation_id, user_id, role, content):
        return None


class _SelectingLLM:
    def __init__(self, decision):
        self.decision = decision
        self.selection_messages = []
        self.final_messages = []

    async def select_tools(self, system_prompt, messages, tools):
        self.selection_prompt = system_prompt
        self.selection_messages = messages
        self.tools = tools
        return self.decision

    async def stream_coaching_response(self, messages):
        self.final_messages = messages
        if '"status": "needs_clarification"' in messages[0]["content"]:
            yield "What date should I use, and how long would you like the session to be?"
        else:
            yield "Here are the best options. Please confirm before anything is added."


def _future_date(days=1):
    return date.today() + timedelta(days=days)


def _planning_service(context, repository=None):
    return CoachingPlanningService(
        context,
        CoachingRecommendationService(),
        repository,
    )


def _chat_service(decision, context, repository=None):
    service = ChatService(None)
    service.context_service = context
    service.repository = repository
    service.recommender = CoachingRecommendationService()
    service.planning_service = _planning_service(context, repository)
    service.tool_registry = CoachToolRegistry(context, service.planning_service)
    service.llm = _SelectingLLM(decision)
    service._open_conversation = lambda _user, _conversation: (None, [])
    return service


def _payloads(events):
    payloads = []
    for event in events:
        raw = event.removeprefix("data: ").strip()
        if raw != "[DONE]":
            payloads.append(json.loads(raw))
    return payloads


def test_ambiguous_planning_request_reports_missing_information_without_querying() -> None:
    context = _PlanningContext()
    repository = _ProposalRepository()
    planning = _planning_service(context, repository)

    outcome = planning.find_available_times(
        "trusted-user",
        FindAvailableTimesArgs(
            mode="create_task_proposal",
            category="Study",
            title="Study",
        ),
        timezone_name="America/Denver",
        conversation_id="conversation-1",
    )

    assert outcome.data["status"] == "needs_clarification"
    assert outcome.data["missing_fields"] == ["planned_date", "duration_minutes"]
    assert outcome.proposal is None
    assert context.calls == []
    assert repository.proposals == []


def test_ambiguous_natural_request_streams_a_safe_followup_question() -> None:
    context = _PlanningContext()
    repository = _ProposalRepository()
    service = _chat_service(
        ToolDecision(
            calls=[
                ToolCall(
                    name="find_available_times",
                    arguments={
                        "mode": "create_task_proposal",
                        "title": "Study",
                        "category": "Study",
                    },
                )
            ]
        ),
        context,
        repository,
    )

    async def collect():
        return [
            event
            async for event in service.stream(
                "trusted-user",
                "I really need to fit in some studying.",
                [],
                timezone_name="America/Denver",
            )
        ]

    payloads = _payloads(asyncio.run(collect()))

    assert payloads == [
        {
            "token": (
                "What date should I use, and how long would you like the session to be?"
            )
        }
    ]
    assert context.calls == []
    assert repository.proposals == []


def test_informational_availability_returns_options_without_a_proposal() -> None:
    context = _PlanningContext()
    repository = _ProposalRepository()
    planning = _planning_service(context, repository)

    outcome = planning.find_available_times(
        "trusted-user",
        FindAvailableTimesArgs(
            mode="suggest_times",
            planned_date=_future_date(),
            duration_minutes=45,
            category="Study",
        ),
        timezone_name="America/Denver",
        conversation_id="conversation-1",
    )

    assert outcome.data["status"] == "options_found"
    assert outcome.data["options"]
    assert outcome.proposal is None
    assert repository.proposals == []


def test_explicit_natural_planning_request_emits_compatible_pending_proposal() -> None:
    target = _future_date()
    repository = _ProposalRepository()
    decision = ToolDecision(
        calls=[
            ToolCall(
                name="find_available_times",
                arguments={
                    "mode": "create_task_proposal",
                    "title": "Study for biology",
                    "category": "Study",
                    "planned_date": target.isoformat(),
                    "duration_minutes": 60,
                },
            )
        ]
    )
    service = _chat_service(decision, _PlanningContext(), repository)

    async def collect():
        return [
            event
            async for event in service.stream(
                "trusted-user",
                "I need to get an hour of biology studying done tomorrow.",
                [],
                timezone_name="America/Denver",
            )
        ]

    events = asyncio.run(collect())
    payloads = _payloads(events)
    proposal = next(payload["proposal"] for payload in payloads if "proposal" in payload)

    assert repository.proposals
    assert repository.proposals[0][0] == "trusted-user"
    assert proposal["id"] == "proposal-42"
    assert set(proposal) == {"id", "task", "options"}
    assert proposal["task"]["title"] == "Study for biology"
    assert events[-1] == "data: [DONE]\n\n"


def test_exact_time_conflict_is_respected_and_does_not_create_proposal() -> None:
    target = _future_date()
    context = _PlanningContext(
        [
            {
                "title": "Class",
                "category": "Study",
                "date": target.isoformat(),
                "time": "10:00",
                "duration_minutes": 60,
            }
        ]
    )
    repository = _ProposalRepository()

    outcome = _planning_service(context, repository).find_available_times(
        "trusted-user",
        FindAvailableTimesArgs(
            mode="create_task_proposal",
            title="Study",
            category="Study",
            planned_date=target,
            duration_minutes=60,
            exact_time="10:00",
        ),
        timezone_name="America/Denver",
        conversation_id=None,
    )

    assert outcome.data["status"] == "no_availability"
    assert outcome.proposal is None
    assert repository.proposals == []


def test_invalid_planning_arguments_and_user_id_override_fail_safely() -> None:
    context = _PlanningContext()
    registry = CoachToolRegistry(context, _planning_service(context))

    invalid_window = registry.execute(
        ToolCall(
            name="find_available_times",
            arguments={
                "mode": "suggest_times",
                "planned_date": _future_date().isoformat(),
                "duration_minutes": 60,
                "earliest_time": "18:00",
                "latest_time": "09:00",
            },
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )
    injected_user = registry.execute(
        ToolCall(
            name="find_available_times",
            arguments={
                "mode": "suggest_times",
                "planned_date": _future_date().isoformat(),
                "duration_minutes": 60,
                "user_id": "attacker",
            },
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )
    invalid_duration = registry.execute(
        ToolCall(
            name="find_available_times",
            arguments={
                "mode": "suggest_times",
                "planned_date": _future_date().isoformat(),
                "duration_minutes": 1000,
            },
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )
    past_date = registry.execute(
        ToolCall(
            name="find_available_times",
            arguments={
                "mode": "suggest_times",
                "planned_date": (date.today() - timedelta(days=1)).isoformat(),
                "duration_minutes": 30,
            },
        ),
        user_id="trusted-user",
        timezone_name="UTC",
    )

    assert invalid_window.ok is False
    assert injected_user.ok is False
    assert invalid_duration.ok is False
    assert past_date.ok is True
    assert past_date.data["status"] == "invalid_request"
    assert context.calls == []


def test_tool_catalog_exposes_no_direct_task_or_calendar_mutation() -> None:
    context = _PlanningContext()
    registry = CoachToolRegistry(context, _planning_service(context))

    definitions = registry.definitions()

    assert next(tool for tool in definitions if tool.name == "find_available_times").kind == (
        "proposal"
    )
    assert not {
        "create_task",
        "update_task",
        "sync_google_calendar",
    }.intersection(tool.name for tool in definitions)


def test_followup_uses_recent_conversation_to_complete_planning_request() -> None:
    target = _future_date()
    repository = _ProposalRepository()
    decision = ToolDecision(
        calls=[
            ToolCall(
                name="find_available_times",
                arguments={
                    "mode": "create_task_proposal",
                    "title": "Study",
                    "category": "Study",
                    "planned_date": target.isoformat(),
                    "duration_minutes": 60,
                },
            )
        ]
    )
    service = _chat_service(decision, _PlanningContext(), repository)
    history = [
        {"role": "user", "content": "I need to study tomorrow."},
        {"role": "assistant", "content": "How long would you like to study?"},
    ]

    async def collect():
        return [
            event
            async for event in service.stream(
                "trusted-user",
                "About an hour.",
                history,
                timezone_name="America/Denver",
            )
        ]

    asyncio.run(collect())

    assert service.llm.selection_messages[-3:] == [
        *history,
        {"role": "user", "content": "About an hour."},
    ]
    assert repository.proposals


def test_planning_can_coexist_with_phase_one_read_tools() -> None:
    target = _future_date()
    context = _PlanningContext()
    repository = _ProposalRepository()
    registry = CoachToolRegistry(context, _planning_service(context, repository))
    results = registry.execute_many(
        [
            ToolCall(name="get_task_performance", arguments={"category": "Study"}),
            ToolCall(name="get_failure_patterns", arguments={"category": "Study"}),
            ToolCall(
                name="find_available_times",
                arguments={
                    "mode": "suggest_times",
                    "planned_date": target.isoformat(),
                    "duration_minutes": 60,
                    "category": "Study",
                },
            ),
        ],
        user_id="trusted-user",
        timezone_name="America/Denver",
    )

    assert [result.name for result in results] == [
        "get_task_performance",
        "get_failure_patterns",
        "find_available_times",
    ]
    assert all(result.ok for result in results)
    assert repository.proposals == []


def test_existing_confirmation_endpoint_accepts_phase_two_proposal(monkeypatch) -> None:
    proposal_id = UUID("00000000-0000-0000-0000-000000000042")
    user_id = UUID("00000000-0000-0000-0000-000000000007")
    candidate_start = f"{_future_date().isoformat()}T09:00:00+00:00"
    task = {
        "title": "Study biology",
        "task_category": "Study",
        "planned_start_time": "09:00",
        "planned_date": _future_date().isoformat(),
        "planned_duration_min": 60,
        "importance": 3,
        "energy_level": 3,
        "focus_level": 3,
        "total_tasks_today": 1,
    }

    class Repository:
        def get_owned_proposal(self, requested_id, requested_user):
            assert requested_id == proposal_id
            assert requested_user == str(user_id)
            return {
                "status": "pending",
                "expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
                "payload": {
                    "task": task,
                    "options": [{"start": candidate_start}],
                },
            }

        def finish_proposal(self, requested_id, requested_user, status, result=None):
            self.finished = (requested_id, requested_user, status, result)

    class Tasks:
        def list_for_user(self, requested_user, planned_date):
            return []

        def create(self, requested_user, payload):
            return {
                "id": "task-1",
                "user_id": requested_user,
                **payload,
                "task_status": "pending",
                "created_at": datetime.now(timezone.utc).isoformat(),
            }

    class Calendar:
        def sync_task_safely(self, requested_user, created):
            self.synced = (requested_user, created)

    repository = Repository()
    tasks = Tasks()
    calendar = Calendar()
    monkeypatch.setattr(chat_route, "is_supabase_configured", lambda: True)
    monkeypatch.setattr(chat_route, "get_supabase", lambda: object())
    monkeypatch.setattr(chat_route, "CoachRepository", lambda _db: repository)
    monkeypatch.setattr(chat_route, "TaskService", lambda _db: tasks)
    monkeypatch.setattr(chat_route, "GoogleCalendarService", lambda _db: calendar)

    created = chat_route.confirm_proposal(
        proposal_id,
        ProposalConfirmRequest(candidate_start=candidate_start),
        user_id,
    )

    assert created["id"] == "task-1"
    assert repository.finished[2] == "confirmed"
    assert calendar.synced[1] == created
