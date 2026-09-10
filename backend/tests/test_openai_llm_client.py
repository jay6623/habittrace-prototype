from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace

import pytest

from app.config import settings
from app.schemas.coach_tools import ToolCall, ToolDecision, ToolResult
from app.services.chat_service import ChatService
from app.services.coach_tool_registry import CoachToolRegistry
from app.services.llm_client import (
    GeminiLLMClient,
    LLMConnectionError,
    LLMProviderError,
    LLMTimeoutError,
    OllamaLLMClient,
    OpenAILLMClient,
    UnsupportedLLMClient,
    _OpenAIToolDecision,
    get_llm_client,
)


class _APIError(Exception):
    def __init__(
        self,
        message: str,
        status_code: int | None = None,
        *,
        body=None,
        request_id: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.body = body
        self.request_id = request_id


class _APITimeoutError(_APIError):
    pass


class _APIConnectionError(_APIError):
    pass


class _RateLimitError(_APIError):
    pass


class _FakeSDK:
    APITimeoutError = _APITimeoutError
    APIConnectionError = _APIConnectionError
    RateLimitError = _RateLimitError


class _Events:
    def __init__(self, events):
        self.events = events

    def __aiter__(self):
        return self._iterate()

    async def _iterate(self):
        for event in self.events:
            if isinstance(event, Exception):
                raise event
            yield event


class _Responses:
    def __init__(self, *, parsed=None, events=None, error=None):
        self.parsed = parsed
        self.events = events or []
        self.error = error
        self.parse_kwargs = None
        self.create_kwargs = None
        self.create_kwargs_history = []
        self.create_count = 0

    async def parse(self, **kwargs):
        self.parse_kwargs = kwargs
        if self.error:
            raise self.error
        parsed = self.parsed
        if isinstance(parsed, ToolDecision):
            parsed = _OpenAIToolDecision(
                calls=[
                    {
                        "name": call.name,
                        "arguments_json": json.dumps(call.arguments),
                    }
                    for call in parsed.calls
                ]
            )
        return SimpleNamespace(output_parsed=parsed)

    async def create(self, **kwargs):
        self.create_kwargs = kwargs
        self.create_kwargs_history.append(kwargs)
        if self.error:
            raise self.error
        if self.events and isinstance(self.events[0], list):
            events = self.events[self.create_count]
            self.create_count += 1
            return _Events(events)
        return _Events(self.events)


class _Client:
    def __init__(self, responses):
        self.responses = responses
        self.closed = False

    async def close(self):
        self.closed = True


def _install_client(monkeypatch, responses, api_key="test-secret-key"):
    client = _Client(responses)
    monkeypatch.setattr(settings, "openai_api_key", api_key)
    monkeypatch.setattr(settings, "openai_model", "gpt-5.6-terra")
    monkeypatch.setattr(settings, "openai_reasoning_effort", "low")
    monkeypatch.setattr(OpenAILLMClient, "_sdk", staticmethod(lambda: _FakeSDK))
    monkeypatch.setattr(
        OpenAILLMClient,
        "_client",
        staticmethod(lambda _sdk, supplied_key: client),
    )
    return client


def test_get_llm_client_selects_all_supported_providers(monkeypatch) -> None:
    expected = {
        "ollama": OllamaLLMClient,
        "gemini": GeminiLLMClient,
        "openai": OpenAILLMClient,
    }

    for provider, client_type in expected.items():
        monkeypatch.setattr(settings, "llm_provider", provider)
        assert isinstance(get_llm_client(), client_type)


def test_unsupported_provider_fails_clearly_and_safely(monkeypatch) -> None:
    monkeypatch.setattr(settings, "llm_provider", "unknown-provider")
    client = get_llm_client()

    assert isinstance(client, UnsupportedLLMClient)
    with pytest.raises(LLMProviderError, match="Unsupported LLM_PROVIDER"):
        asyncio.run(client.select_tools("system", [], []))


def test_missing_openai_api_key_fails_safely(monkeypatch) -> None:
    monkeypatch.setattr(settings, "openai_api_key", "")

    with pytest.raises(LLMProviderError, match="OPENAI_API_KEY is required"):
        asyncio.run(OpenAILLMClient().select_tools("system", [], []))


def test_openai_client_uses_bounded_sdk_retries() -> None:
    captured = {}

    class SDK:
        @staticmethod
        def AsyncOpenAI(**kwargs):
            captured.update(kwargs)
            return object()

    OpenAILLMClient._client(SDK, "test-secret-key")

    assert captured == {
        "api_key": "test-secret-key",
        "timeout": 90.0,
        "max_retries": 2,
    }


@pytest.mark.parametrize(
    "decision",
    [
        ToolDecision(),
        ToolDecision(
            calls=[
                ToolCall(name="get_task_performance", arguments={"category": "Study"}),
                ToolCall(
                    name="find_available_times",
                    arguments={
                        "mode": "suggest_times",
                        "planned_date": "2026-09-11",
                        "duration_minutes": 60,
                    },
                ),
            ]
        ),
    ],
)
def test_openai_structured_tool_decision_uses_existing_contract(
    monkeypatch, decision
) -> None:
    responses = _Responses(parsed=decision)
    client = _install_client(monkeypatch, responses)

    result = asyncio.run(
        OpenAILLMClient().select_tools(
            "Select only necessary tools.",
            [{"role": "user", "content": "How is studying going?"}],
            [],
        )
    )

    assert result == decision
    assert responses.parse_kwargs["model"] == "gpt-5.6-terra"
    assert responses.parse_kwargs["text_format"] is _OpenAIToolDecision
    assert responses.parse_kwargs["reasoning"] == {"effort": "low"}
    assert responses.parse_kwargs["store"] is False
    assert responses.parse_kwargs["input"][-1] == {
        "role": "user",
        "content": "How is studying going?",
    }
    assert "test-secret-key" not in str(responses.parse_kwargs)
    assert client.closed is True


def test_openai_structured_tool_request_uses_api_compatible_strict_schema(
    monkeypatch,
) -> None:
    from openai.lib._parsing._responses import type_to_text_format_param

    decision = ToolDecision(
        calls=[
            ToolCall(
                name="find_available_times",
                arguments={
                    "mode": "create_task_proposal",
                    "planned_date": "2026-09-11",
                    "duration_minutes": 60,
                    "title": "Study",
                    "category": "Study",
                    "exact_time": "16:00",
                },
            )
        ]
    )
    responses = _Responses(parsed=decision)
    _install_client(monkeypatch, responses)

    result = asyncio.run(OpenAILLMClient().select_tools("system", [], []))

    text_format = type_to_text_format_param(responses.parse_kwargs["text_format"])
    schema = text_format["schema"]
    tool_call_schema = schema["$defs"]["_OpenAIToolCall"]
    assert text_format["type"] == "json_schema"
    assert text_format["strict"] is True
    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == {"calls"}
    assert tool_call_schema["additionalProperties"] is False
    assert set(tool_call_schema["required"]) == {"name", "arguments_json"}
    assert tool_call_schema["properties"]["arguments_json"]["type"] == "string"
    assert result == decision


def test_chat_service_sends_planning_followup_history_and_roles_to_openai(
    monkeypatch,
) -> None:
    responses = _Responses(parsed=ToolDecision())
    _install_client(monkeypatch, responses)

    history = [
        {"role": "user", "content": "Find me an hour to study tomorrow."},
        {
            "role": "assistant",
            "content": "I found openings at 9:00 AM and 4:00 PM tomorrow.",
        },
    ]
    service = ChatService(None)
    service.llm = OpenAILLMClient()
    service.tool_registry = CoachToolRegistry(object())

    asyncio.run(
        service._select_coaching_context(
            "trusted-user",
            "4 PM works. Schedule it.",
            history,
            "America/Denver",
            "conversation-1",
        )
    )

    sent = responses.parse_kwargs["input"]
    assert sent[1:] == [
        *history,
        {"role": "user", "content": "4 PM works. Schedule it."},
    ]
    assert [message["role"] for message in sent] == [
        "system",
        "user",
        "assistant",
        "user",
    ]
    assert "PLANNING FOLLOW-UPS" in sent[0]["content"]
    assert "retain the earlier title/category/date/duration" in sent[0]["content"]
    assert "never use an acknowledgement" in sent[0]["content"]
    assert "mapping a selected recommended time to exact_time" in sent[0]["content"]
    assert "morning ends at 12:00" in sent[0]["content"]
    assert 'For "after X", set only earliest_time' in sent[0]["content"]
    assert '"before X", set only latest_time' in sent[0]["content"]
    find_times = next(
        tool for tool in service.tool_registry.definitions() if tool.name == "find_available_times"
    )
    properties = find_times.input_schema["properties"]
    assert "Hard lower bound" in properties["earliest_time"]["description"]
    assert "Hard upper bound" in properties["latest_time"]["description"]


def test_openai_malformed_structured_output_fails_safely(monkeypatch) -> None:
    responses = _Responses(parsed={"calls": "not-a-list"})
    _install_client(monkeypatch, responses)

    with pytest.raises(LLMProviderError, match="malformed tool selection"):
        asyncio.run(OpenAILLMClient().select_tools("system", [], []))


def test_openai_stream_yields_only_visible_text(monkeypatch) -> None:
    responses = _Responses(
        events=[
            SimpleNamespace(type="response.created"),
            SimpleNamespace(type="response.reasoning_text.delta", delta="hidden"),
            SimpleNamespace(type="response.output_text.delta", delta="Hello"),
            SimpleNamespace(type="response.output_text.delta", delta=" there"),
            SimpleNamespace(type="response.completed"),
        ]
    )
    client = _install_client(monkeypatch, responses)

    async def collect():
        return [
            token
            async for token in OpenAILLMClient().stream_coaching_response(
                [{"role": "user", "content": "Hi"}]
            )
        ]

    assert asyncio.run(collect()) == ["Hello", " there"]
    assert responses.create_kwargs["stream"] is True
    assert responses.create_kwargs["model"] == "gpt-5.6-terra"
    assert client.closed is True


def test_openai_native_tool_loop_returns_only_selected_data(monkeypatch) -> None:
    function_call = SimpleNamespace(
        type="function_call",
        name="get_task_performance",
        arguments=json.dumps({"category": "Study"}),
        call_id="call-1",
    )
    tool_response = SimpleNamespace(output=[function_call], output_text="")
    final_response = SimpleNamespace(output=[], output_text="")
    responses = _Responses(
        events=[
            [SimpleNamespace(type="response.completed", response=tool_response)],
            [
                SimpleNamespace(type="response.output_text.delta", delta="Study is improving."),
                SimpleNamespace(type="response.completed", response=final_response),
            ],
        ]
    )
    client = _install_client(monkeypatch, responses)
    executed = []

    def execute_tools(calls):
        executed.extend(calls)
        return [
            ToolResult(
                name="get_task_performance",
                ok=True,
                data={"success_rate": 75.0, "sample_size": 8},
            )
        ]

    tools = [
        SimpleNamespace(
            name="get_task_performance",
            description="Get scoped performance.",
            input_schema={"type": "object", "properties": {}},
        )
    ]

    async def collect():
        return [
            token
            async for token in OpenAILLMClient().stream_coaching_response_with_tools(
                [{"role": "user", "content": "How is studying going?"}],
                tools,
                execute_tools,
            )
        ]

    assert asyncio.run(collect()) == ["Study is improving."]
    assert executed == [
        ToolCall(name="get_task_performance", arguments={"category": "Study"})
    ]
    assert len(responses.create_kwargs_history) == 2
    first_request = responses.create_kwargs_history[0]
    assert first_request["tool_choice"] == "auto"
    assert first_request["tools"][0]["name"] == "get_task_performance"
    second_input = responses.create_kwargs_history[1]["input"]
    tool_output = second_input[-1]
    assert tool_output["type"] == "function_call_output"
    assert json.loads(tool_output["output"])["data"] == {
        "success_rate": 75.0,
        "sample_size": 8,
    }
    assert client.closed is True


def test_chat_service_uses_native_openai_turn_and_limits_history(monkeypatch) -> None:
    final_response = SimpleNamespace(output=[], output_text="")
    responses = _Responses(
        events=[
            SimpleNamespace(type="response.output_text.delta", delta="현재 질문에 답합니다."),
            SimpleNamespace(type="response.completed", response=final_response),
        ]
    )
    _install_client(monkeypatch, responses)
    service = ChatService(None)
    service.llm = OpenAILLMClient()
    history = [
        {"role": "user" if index % 2 == 0 else "assistant", "content": f"old-{index}"}
        for index in range(12)
    ]

    async def collect():
        return [
            event
            async for event in service.stream(
                "user-1",
                "지금 질문에 답해줘",
                history,
                timezone_name="Asia/Seoul",
            )
        ]

    events = asyncio.run(collect())
    sent = responses.create_kwargs["input"]

    payloads = [
        json.loads(event.removeprefix("data: ").strip())
        for event in events
        if "[DONE]" not in event
    ]
    assert {"token": "현재 질문에 답합니다."} in payloads
    assert responses.parse_kwargs is None
    assert len(sent) == 10  # system + eight recent messages + current user message
    assert sent[1]["content"] == "old-4"
    assert sent[-1] == {"role": "user", "content": "지금 질문에 답해줘"}
    assert "Respond in the language the user is using" in sent[0]["content"]
    assert responses.create_kwargs["tools"] == []


@pytest.mark.parametrize(
    ("error", "expected_type", "message"),
    [
        (_APITimeoutError("secret test-secret-key"), LLMTimeoutError, "timed out"),
        (_APIConnectionError("secret test-secret-key"), LLMConnectionError, "connect"),
        (_RateLimitError("secret test-secret-key", 429), LLMProviderError, "usage limit"),
        (_APIError("secret test-secret-key", 503), LLMProviderError, "temporarily busy"),
    ],
)
def test_openai_provider_errors_are_safe(
    monkeypatch, error, expected_type, message
) -> None:
    responses = _Responses(error=error)
    _install_client(monkeypatch, responses)

    with pytest.raises(expected_type, match=message) as caught:
        asyncio.run(OpenAILLMClient().select_tools("system", [], []))

    assert "test-secret-key" not in str(caught.value)


def test_openai_400_logs_sanitized_schema_diagnostics(monkeypatch, caplog) -> None:
    error = _APIError(
        "request failed with test-secret-key",
        400,
        body={
            "error": {
                "type": "invalid_request_error",
                "code": "invalid_json_schema",
                "param": "text.format.schema",
                "message": "Invalid schema involving test-secret-key",
            }
        },
        request_id="req_test",
    )
    responses = _Responses(error=error)
    _install_client(monkeypatch, responses)

    with (
        caplog.at_level("ERROR", logger="app.services.llm_client"),
        pytest.raises(LLMProviderError, match="OpenAI API error") as caught,
    ):
        asyncio.run(OpenAILLMClient().select_tools("system", [], []))

    assert "status=400" in caplog.text
    assert "request_id=req_test" in caplog.text
    assert "code=invalid_json_schema" in caplog.text
    assert "param=text.format.schema" in caplog.text
    assert "Invalid schema involving [REDACTED]" in caplog.text
    assert "test-secret-key" not in caplog.text
    assert "test-secret-key" not in str(caught.value)


def test_openai_incomplete_or_empty_stream_fails_safely(monkeypatch) -> None:
    incomplete = _Responses(events=[SimpleNamespace(type="response.incomplete")])
    _install_client(monkeypatch, incomplete)

    async def collect_incomplete():
        return [token async for token in OpenAILLMClient().stream_coaching_response([])]

    with pytest.raises(LLMProviderError, match="incomplete"):
        asyncio.run(collect_incomplete())

    empty = _Responses(events=[SimpleNamespace(type="response.completed")])
    _install_client(monkeypatch, empty)

    async def collect_empty():
        return [token async for token in OpenAILLMClient().stream_coaching_response([])]

    with pytest.raises(LLMProviderError, match="did not return a text response"):
        asyncio.run(collect_empty())


def test_openai_stream_server_error_is_sanitized(monkeypatch) -> None:
    responses = _Responses(error=_APIError("secret test-secret-key", 503))
    _install_client(monkeypatch, responses)

    async def collect():
        return [token async for token in OpenAILLMClient().stream_coaching_response([])]

    with pytest.raises(LLMProviderError, match="temporarily busy") as caught:
        asyncio.run(collect())

    assert "test-secret-key" not in str(caught.value)
