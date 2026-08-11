"""Shared Supabase/PostgREST error translation for repositories."""
from __future__ import annotations

import logging
from typing import Any

import httpx
from postgrest.exceptions import APIError
from supabase import Client

from ..core.errors import (
    DatabaseUnavailableError,
    DomainValidationError,
    RepositoryError,
    ResourceConflictError,
)

logger = logging.getLogger(__name__)


class BaseRepository:
    def __init__(self, db: Client) -> None:
        self.db = db

    def _execute(
        self,
        query: Any,
        *,
        conflict_detail: str = "The resource already exists.",
        validation_detail: str = "The data violates a database constraint.",
    ) -> Any:
        try:
            return query.execute()
        except APIError as exc:
            logger.error(
                "PostgREST operation failed (code=%s, message=%s, details=%s)",
                exc.code,
                getattr(exc, "message", None),
                getattr(exc, "details", None),
            )
            if exc.code == "23505":
                raise ResourceConflictError(conflict_detail) from exc
            if exc.code in {"23502", "23503", "23514", "22P02"}:
                raise DomainValidationError(validation_detail) from exc
            raise RepositoryError() from exc
        except httpx.TransportError as exc:
            logger.error(
                "Supabase network operation failed (%s): %s",
                type(exc).__name__,
                str(exc) or "no transport details",
            )
            raise DatabaseUnavailableError() from exc
        except (KeyError, IndexError, TypeError) as exc:
            logger.error("Supabase returned an unexpected response shape")
            raise RepositoryError() from exc
