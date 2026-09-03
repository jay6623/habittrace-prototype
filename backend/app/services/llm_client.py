"""LLM provider boundary for the HabitTrace coach."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncGenerator

import httpx
from pydantic import ValidationError

from ..config import settings
from ..schemas.chat import AgentIntent

logger = logging.getLogger(__name__)

ChatMessage = dict[str, str]


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
                        "Ollama returned an error. Confirm that the configured "
                        "model is installed."
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


def get_llm_client() -> OllamaLLMClient:
    return OllamaLLMClient()
