"""LLM provider boundary for the HabitTrace coach."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncGenerator
from typing import NoReturn, Protocol

import httpx
from pydantic import ValidationError

from ..config import settings
from ..schemas.chat import AgentIntent
from ..schemas.coach_tools import ToolDecision, ToolDefinition

logger = logging.getLogger(__name__)

ChatMessage = dict[str, str]
GEMINI_RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}
GEMINI_TRANSIENT_ERROR_MESSAGE = "The AI coach is temporarily busy. Please try again in a minute."
GEMINI_QUOTA_ERROR_MESSAGE = "The AI coach usage limit has been reached. Please try again later."
GEMINI_API_ERROR_MESSAGE = "Gemini API error. Please try again later."
GEMINI_INCOMPLETE_RESPONSE_MESSAGE = "The AI coach response was incomplete. Please try again."


class LLMClient(Protocol):
    async def classify_intent(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
    ) -> AgentIntent: ...

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
    async def classify_intent(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
    ) -> AgentIntent:
        payload = {
            "model": settings.ollama_model,
            "messages": [{"role": "system", "content": system_prompt}, *messages],
            "stream": False,
            "format": AgentIntent.model_json_schema(),
            "options": {"temperature": 0, "num_predict": 300},
        }
        try:
            async with httpx.AsyncClient(timeout=60.0) as client:
                response = await client.post(settings.ollama_chat_url, json=payload)
                response.raise_for_status()
            content = response.json().get("message", {}).get("content", "{}")
            return AgentIntent.model_validate_json(content)
        except httpx.ConnectError as exc:
            raise LLMConnectionError(
                "Cannot connect to Ollama. Start it with `ollama serve`."
            ) from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError(
                "Ollama timed out while loading or generating a response."
            ) from exc
        except (httpx.HTTPError, ValueError, ValidationError, TypeError) as exc:
            raise LLMProviderError("Structured intent parsing failed.") from exc

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

    async def classify_intent(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
    ) -> AgentIntent:
        api_key = self._api_key()
        genai, errors, types = self._sdk()
        client = None
        try:
            client = self._client(genai, types, api_key)
            response = await client.models.generate_content(
                model=settings.gemini_model,
                contents=self._contents(messages, types),
                config=types.GenerateContentConfig(
                    system_instruction=system_prompt,
                    temperature=0,
                    max_output_tokens=300,
                    response_mime_type="application/json",
                    response_json_schema=AgentIntent.model_json_schema(),
                ),
            )
            content = getattr(response, "text", None)
            if not content:
                raise LLMProviderError("Gemini returned an empty intent response.")
            return AgentIntent.model_validate_json(content)
        except errors.APIError as exc:
            self._raise_api_error(exc)
        except httpx.ConnectError as exc:
            raise LLMConnectionError("Cannot connect to the Gemini API.") from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("The Gemini API request timed out.") from exc
        except LLMClientError:
            raise
        except (ValueError, ValidationError, TypeError) as exc:
            raise LLMProviderError("Gemini returned malformed structured output.") from exc
        finally:
            if client is not None:
                await client.aclose()

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

    async def classify_intent(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
    ) -> AgentIntent:
        raise LLMProviderError(
            f"Unsupported LLM_PROVIDER={self.provider!r}. Use 'ollama' or 'gemini'."
        )

    async def select_tools(
        self,
        system_prompt: str,
        messages: list[ChatMessage],
        tools: list[ToolDefinition],
    ) -> ToolDecision:
        raise LLMProviderError(
            f"Unsupported LLM_PROVIDER={self.provider!r}. Use 'ollama' or 'gemini'."
        )

    async def stream_coaching_response(
        self,
        messages: list[ChatMessage],
    ) -> AsyncGenerator[str, None]:
        raise LLMProviderError(
            f"Unsupported LLM_PROVIDER={self.provider!r}. Use 'ollama' or 'gemini'."
        )
        yield ""


def get_llm_client() -> LLMClient:
    provider = (settings.llm_provider or "ollama").strip().lower()
    if provider == "ollama":
        return OllamaLLMClient()
    if provider == "gemini":
        return GeminiLLMClient()
    logger.error("Unsupported LLM_PROVIDER configured: %s", settings.llm_provider)
    return UnsupportedLLMClient(settings.llm_provider)
