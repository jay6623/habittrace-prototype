"""LLM provider boundary for the HabitTrace coach."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncGenerator
from typing import Any, NoReturn, Protocol

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from ..config import settings
from ..schemas.coach_tools import ToolDecision, ToolDefinition

logger = logging.getLogger(__name__)

ChatMessage = dict[str, str]
GEMINI_RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}
GEMINI_TRANSIENT_ERROR_MESSAGE = "The AI coach is temporarily busy. Please try again in a minute."
GEMINI_QUOTA_ERROR_MESSAGE = "The AI coach usage limit has been reached. Please try again later."
GEMINI_API_ERROR_MESSAGE = "Gemini API error. Please try again later."
GEMINI_INCOMPLETE_RESPONSE_MESSAGE = "The AI coach response was incomplete. Please try again."
OPENAI_TRANSIENT_ERROR_MESSAGE = "The AI coach is temporarily busy. Please try again in a minute."
OPENAI_QUOTA_ERROR_MESSAGE = "The AI coach usage limit has been reached. Please try again later."
OPENAI_API_ERROR_MESSAGE = "OpenAI API error. Please try again later."
OPENAI_INCOMPLETE_RESPONSE_MESSAGE = "The AI coach response was incomplete. Please try again."


class _OpenAIToolCall(BaseModel):
    """OpenAI-compatible wire shape for one provider-neutral tool call."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=100)
    arguments_json: str = Field(
        description="A JSON-encoded object containing only the selected tool's arguments."
    )


class _OpenAIToolDecision(BaseModel):
    """Strict structured-output envelope converted to ToolDecision after parsing."""

    model_config = ConfigDict(extra="forbid")

    calls: list[_OpenAIToolCall] = Field(default_factory=list, max_length=4)


class LLMClient(Protocol):
    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision: ...

    def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]: ...


class LLMClientError(Exception):
    """Base class for provider failures that callers can safely recover from."""


class LLMConnectionError(LLMClientError):
    """Raised when the configured LLM provider cannot be reached."""


class LLMTimeoutError(LLMClientError):
    """Raised when the configured LLM provider times out."""


class LLMProviderError(LLMClientError):
    """Raised when the provider returns an unusable response."""


class OllamaLLMClient:
    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision:
        tool_catalog = json.dumps([tool.model_dump() for tool in tools])
        payload = {
            "model": settings.ollama_model,
            "messages": [
                {
                    "role": "system",
                    "content": f"{system_prompt}\n\nAVAILABLE_TOOLS_JSON:\n{tool_catalog}",
                },
                *messages,
            ],
            "stream": False,
            "format": ToolDecision.model_json_schema(),
            "options": {"temperature": 0, "num_predict": 500},
        }
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(settings.ollama_chat_url, json=payload)
                response.raise_for_status()
            content = response.json().get("message", {}).get("content", "{}")
            return ToolDecision.model_validate_json(content)
        except httpx.ConnectError as exc:
            raise LLMConnectionError(
                "Cannot connect to Ollama. Start it with `ollama serve`."
            ) from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("Ollama timed out while selecting coach tools.") from exc
        except (httpx.HTTPError, ValueError, ValidationError, TypeError) as exc:
            raise LLMProviderError("Coach tool selection failed.") from exc

    async def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]:
        try:
            async with (
                httpx.AsyncClient(timeout=90.0) as client,
                client.stream(
                    "POST",
                    settings.ollama_chat_url,
                    json={
                        "model": settings.ollama_model,
                        "messages": messages,
                        "stream": True,
                        "options": {"temperature": 0.5, "num_predict": 500},
                    },
                ) as response,
            ):
                if response.status_code != 200:
                    raise LLMProviderError(
                        "Ollama returned an error. Confirm that the configured model is installed."
                    )
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    try:
                        chunk = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    token = chunk.get("message", {}).get("content", "")
                    if token:
                        yield token
                    if chunk.get("done"):
                        break
        except httpx.ConnectError as exc:
            raise LLMConnectionError(
                "Cannot connect to Ollama. Start it with `ollama serve`."
            ) from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError(
                "Ollama timed out while loading or generating a response."
            ) from exc


class OpenAILLMClient:
    """OpenAI Responses API adapter for the provider-neutral coach contract."""

    def _api_key(self) -> str:
        api_key = (settings.openai_api_key or "").strip()
        if not api_key:
            raise LLMProviderError("OPENAI_API_KEY is required when LLM_PROVIDER=openai.")
        return api_key

    @staticmethod
    def _sdk() -> Any:
        try:
            import openai
        except ImportError as exc:
            raise LLMProviderError(
                "openai is not installed. Run `pip install -r requirements.txt`."
            ) from exc
        return openai

    @staticmethod
    def _client(sdk: Any, api_key: str) -> Any:
        return sdk.AsyncOpenAI(
            api_key=api_key,
            timeout=90.0,
            max_retries=2,
        )

    @staticmethod
    async def _close_client(client: Any | None) -> None:
        if client is None:
            return
        try:
            await client.close()
        except Exception:
            logger.debug("Could not close OpenAI client cleanly")

    @staticmethod
    def _diagnostic_value(value: Any, api_key: str) -> str | None:
        if value is None:
            return None
        sanitized = " ".join(str(value).split())[:1000]
        if api_key:
            sanitized = sanitized.replace(api_key, "[REDACTED]")
        return sanitized

    @classmethod
    def _log_api_error(cls, exc: Exception, api_key: str) -> None:
        body = getattr(exc, "body", None)
        error = body.get("error", body) if isinstance(body, dict) else {}
        if not isinstance(error, dict):
            error = {}
        logger.error(
            "OpenAI API request failed: status=%s request_id=%s type=%s code=%s "
            "param=%s message=%s",
            getattr(exc, "status_code", None),
            cls._diagnostic_value(getattr(exc, "request_id", None), api_key),
            cls._diagnostic_value(error.get("type"), api_key),
            cls._diagnostic_value(error.get("code"), api_key),
            cls._diagnostic_value(error.get("param"), api_key),
            cls._diagnostic_value(error.get("message") or str(exc), api_key),
        )

    @classmethod
    def _raise_api_error(cls, sdk: Any, exc: Exception, api_key: str) -> NoReturn:
        cls._log_api_error(exc, api_key)
        if isinstance(exc, sdk.APITimeoutError):
            raise LLMTimeoutError("The OpenAI API request timed out.") from exc
        if isinstance(exc, sdk.APIConnectionError):
            raise LLMConnectionError("Cannot connect to the OpenAI API.") from exc
        if isinstance(exc, sdk.RateLimitError) or getattr(exc, "status_code", None) == 429:
            raise LLMProviderError(OPENAI_QUOTA_ERROR_MESSAGE) from exc
        if getattr(exc, "status_code", None) in {408, 409, 500, 502, 503, 504}:
            raise LLMProviderError(OPENAI_TRANSIENT_ERROR_MESSAGE) from exc
        raise LLMProviderError(OPENAI_API_ERROR_MESSAGE) from exc

    @staticmethod
    def _reasoning() -> dict[str, str]:
        return {"effort": settings.openai_reasoning_effort}

    @staticmethod
    def _tool_decision(decision: _OpenAIToolDecision) -> ToolDecision:
        calls = []
        for call in decision.calls:
            arguments = json.loads(call.arguments_json)
            if not isinstance(arguments, dict):
                raise ValueError("OpenAI tool arguments must decode to an object.")
            calls.append({"name": call.name, "arguments": arguments})
        return ToolDecision.model_validate({"calls": calls})

    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision:
        api_key = self._api_key()
        sdk = self._sdk()
        client = None
        tool_catalog = json.dumps([tool.model_dump() for tool in tools])
        input_messages = [
            {
                "role": "system",
                "content": f"{system_prompt}\n\nAVAILABLE_TOOLS_JSON:\n{tool_catalog}",
            },
            *messages,
        ]
        try:
            client = self._client(sdk, api_key)
            response = await client.responses.parse(
                model=settings.openai_model,
                input=input_messages,
                text_format=_OpenAIToolDecision,
                reasoning=self._reasoning(),
                max_output_tokens=max(500, settings.openai_max_output_tokens),
                store=False,
            )
            decision = getattr(response, "output_parsed", None)
            if decision is None:
                raise LLMProviderError("OpenAI returned no structured tool decision.")
            return self._tool_decision(_OpenAIToolDecision.model_validate(decision))
        except LLMClientError:
            raise
        except (ValidationError, ValueError, TypeError) as exc:
            raise LLMProviderError("OpenAI returned malformed tool selection output.") from exc
        except Exception as exc:
            self._raise_api_error(sdk, exc, api_key)
        finally:
            await self._close_client(client)

    async def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]:
        api_key = self._api_key()
        sdk = self._sdk()
        client = None
        emitted_text = False
        try:
            client = self._client(sdk, api_key)
            stream = await client.responses.create(
                model=settings.openai_model,
                input=messages,
                reasoning=self._reasoning(),
                max_output_tokens=max(500, settings.openai_max_output_tokens),
                store=False,
                stream=True,
            )
            async for event in stream:
                event_type = getattr(event, "type", None)
                if event_type == "response.output_text.delta":
                    delta = getattr(event, "delta", None)
                    if isinstance(delta, str) and delta:
                        emitted_text = emitted_text or bool(delta.strip())
                        yield delta
                elif event_type == "response.incomplete":
                    raise LLMProviderError(OPENAI_INCOMPLETE_RESPONSE_MESSAGE)
                elif event_type in {"response.failed", "error"}:
                    raise LLMProviderError(OPENAI_TRANSIENT_ERROR_MESSAGE)
            if not emitted_text:
                raise LLMProviderError(
                    "The AI coach did not return a text response. Please try again."
                )
        except LLMClientError:
            raise
        except Exception as exc:
            self._raise_api_error(sdk, exc, api_key)
        finally:
            await self._close_client(client)


class GeminiLLMClient:
    def _api_key(self) -> str:
        api_key = (settings.gemini_api_key or "").strip()
        if not api_key:
            raise LLMProviderError("GEMINI_API_KEY is required when LLM_PROVIDER=gemini.")
        return api_key

    @staticmethod
    def _sdk():
        try:
            from google import genai
            from google.genai import errors, types
        except ImportError as exc:
            raise LLMProviderError(
                "google-genai is not installed. Run `pip install -r requirements.txt`."
            ) from exc
        return genai, errors, types

    @staticmethod
    def _client(genai: object, types: object, api_key: str) -> object:
        return genai.Client(
            api_key=api_key,
            http_options=types.HttpOptions(
                retry_options=types.HttpRetryOptions(
                    attempts=3,
                    initial_delay=1.0,
                    max_delay=4.0,
                    exp_base=2,
                    jitter=1.0,
                    http_status_codes=sorted(GEMINI_RETRYABLE_STATUS_CODES),
                )
            ),
        ).aio

    @staticmethod
    def _raise_api_error(exc: Exception) -> NoReturn:
        code = getattr(exc, "code", None)
        if code == 429:
            raise LLMProviderError(GEMINI_QUOTA_ERROR_MESSAGE) from exc
        if code in GEMINI_RETRYABLE_STATUS_CODES:
            raise LLMProviderError(GEMINI_TRANSIENT_ERROR_MESSAGE) from exc
        raise LLMProviderError(GEMINI_API_ERROR_MESSAGE) from exc

    @staticmethod
    def _extract_text(chunk: object) -> str:
        try:
            text = getattr(chunk, "text", None)
        except (AttributeError, TypeError, ValueError):
            text = None
        if isinstance(text, str) and text:
            return text

        parts_text: list[str] = []
        candidates = getattr(chunk, "candidates", None) or []
        for candidate in candidates:
            content = getattr(candidate, "content", None)
            parts = getattr(content, "parts", None) or []
            for part in parts:
                if getattr(part, "thought", False):
                    continue
                part_text = getattr(part, "text", None)
                if isinstance(part_text, str) and part_text:
                    parts_text.append(part_text)
        return "".join(parts_text)

    @staticmethod
    def _finish_reason(chunk: object) -> str | None:
        candidates = getattr(chunk, "candidates", None) or []
        if not candidates:
            return None
        reason = getattr(candidates[0], "finish_reason", None)
        if reason is None:
            return None
        name = getattr(reason, "name", None)
        return str(name or reason).removeprefix("FinishReason.").upper()

    @staticmethod
    def _ensure_complete_finish(reason: str | None) -> None:
        if reason in {None, "STOP", "FINISH_REASON_UNSPECIFIED"}:
            return
        if reason == "MAX_TOKENS":
            raise LLMProviderError("The AI coach reached its response limit. Please try again.")
        raise LLMProviderError(GEMINI_INCOMPLETE_RESPONSE_MESSAGE)

    @staticmethod
    def _role(role: str) -> str:
        if role == "assistant":
            return "model"
        return "user"

    def _contents(self, messages: list[ChatMessage], types: object) -> list[object]:
        contents = []
        for message in messages:
            role = str(message.get("role") or "user")
            content = str(message.get("content") or "")
            if role == "system" or not content:
                continue
            contents.append(
                types.Content(
                    role=self._role(role),
                    parts=[types.Part.from_text(text=content)],
                )
            )
        return contents

    @staticmethod
    def _system_instruction(messages: list[ChatMessage]) -> str | None:
        parts = [
            str(message.get("content"))
            for message in messages
            if message.get("role") == "system" and message.get("content")
        ]
        return "\n\n".join(parts) if parts else None

    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision:
        api_key = self._api_key()
        genai, errors, types = self._sdk()
        client = None
        tool_catalog = json.dumps([tool.model_dump() for tool in tools])
        try:
            client = self._client(genai, types, api_key)
            response = await client.models.generate_content(
                model=settings.gemini_model,
                contents=self._contents(messages, types),
                config=types.GenerateContentConfig(
                    system_instruction=(
                        f"{system_prompt}\n\nAVAILABLE_TOOLS_JSON:\n{tool_catalog}"
                    ),
                    temperature=0,
                    max_output_tokens=500,
                    response_mime_type="application/json",
                    response_json_schema=ToolDecision.model_json_schema(),
                ),
            )
            content = getattr(response, "text", None)
            if not content:
                raise LLMProviderError("Gemini returned an empty tool decision.")
            return ToolDecision.model_validate_json(content)
        except errors.APIError as exc:
            self._raise_api_error(exc)
        except httpx.ConnectError as exc:
            raise LLMConnectionError("Cannot connect to the Gemini API.") from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("The Gemini API request timed out.") from exc
        except LLMClientError:
            raise
        except (ValueError, ValidationError, TypeError) as exc:
            raise LLMProviderError("Gemini returned malformed tool selection output.") from exc
        finally:
            if client is not None:
                await client.aclose()

    async def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]:
        api_key = self._api_key()
        genai, errors, types = self._sdk()
        client = None
        try:
            client = self._client(genai, types, api_key)
            stream = await client.models.generate_content_stream(
                model=settings.gemini_model,
                contents=self._contents(messages, types),
                config=types.GenerateContentConfig(
                    system_instruction=self._system_instruction(messages),
                    temperature=0.5,
                    max_output_tokens=max(500, settings.gemini_max_output_tokens),
                ),
            )
            emitted_text = False
            finish_reason: str | None = None
            async for chunk in stream:
                chunk_finish_reason = self._finish_reason(chunk)
                if chunk_finish_reason is not None:
                    finish_reason = chunk_finish_reason
                token = self._extract_text(chunk)
                if token:
                    emitted_text = emitted_text or bool(token.strip())
                    yield token
            if not emitted_text:
                raise LLMProviderError(
                    "The AI coach did not return a text response. Please try again."
                )
            self._ensure_complete_finish(finish_reason)
        except errors.APIError as exc:
            self._raise_api_error(exc)
        except httpx.ConnectError as exc:
            raise LLMConnectionError("Cannot connect to the Gemini API.") from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("The Gemini API request timed out.") from exc
        except LLMClientError:
            raise
        except (ValueError, TypeError) as exc:
            raise LLMProviderError("Gemini returned an unusable stream.") from exc
        finally:
            if client is not None:
                await client.aclose()


class UnsupportedLLMClient:
    def __init__(self, provider: str) -> None:
        self.provider = provider

    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision:
        raise LLMProviderError(
            f"Unsupported LLM_PROVIDER={self.provider!r}. Use 'ollama', 'gemini', or 'openai'."
        )

    async def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]:
        raise LLMProviderError(
            f"Unsupported LLM_PROVIDER={self.provider!r}. Use 'ollama', 'gemini', or 'openai'."
        )
        yield ""


def get_llm_client() -> LLMClient:
    provider = (settings.llm_provider or "ollama").strip().lower()
    if provider == "ollama":
        return OllamaLLMClient()
    if provider == "gemini":
        return GeminiLLMClient()
    if provider == "openai":
        return OpenAILLMClient()
    logger.error("Unsupported LLM_PROVIDER configured: %s", settings.llm_provider)
    return UnsupportedLLMClient(settings.llm_provider)
