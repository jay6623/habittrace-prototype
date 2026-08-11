from __future__ import annotations

from types import SimpleNamespace
from typing import Any, cast

import httpx
import pytest
from postgrest.exceptions import APIError
from supabase import Client

from app.core.errors import (
    DatabaseUnavailableError,
    DomainValidationError,
    ResourceConflictError,
)
from app.repositories.ai_plan_repository import AIPlanRepository
from app.repositories.base import BaseRepository

from .conftest import USER_ID


class RaisingQuery:
    def __init__(self, error: Exception) -> None:
        self.error = error

    def execute(self) -> None:
        raise self.error


def _api_error(code: str) -> APIError:
    return APIError({"code": code, "message": "private", "hint": None, "details": None})


def test_repository_maps_unique_violation() -> None:
    repository = BaseRepository(cast(Client, None))
    with pytest.raises(ResourceConflictError):
        repository._execute(RaisingQuery(_api_error("23505")))


def test_repository_maps_foreign_key_violation() -> None:
    repository = BaseRepository(cast(Client, None))
    with pytest.raises(DomainValidationError):
        repository._execute(RaisingQuery(_api_error("23503")))


def test_repository_maps_all_http_transport_errors() -> None:
    repository = BaseRepository(cast(Client, None))
    with pytest.raises(DatabaseUnavailableError):
        repository._execute(RaisingQuery(httpx.RemoteProtocolError("disconnected")))


class PaginatedQuery:
    def __init__(
        self,
        rows: list[dict[str, Any]],
        calls: list[tuple[int, int]],
        max_page_size: int,
    ) -> None:
        self.rows = rows
        self.calls = calls
        self.max_page_size = max_page_size
        self.start = 0
        self.end = 0

    def select(self, _columns: str) -> PaginatedQuery:
        return self

    def eq(self, _column: str, _value: str) -> PaginatedQuery:
        return self

    def order(self, _column: str) -> PaginatedQuery:
        return self

    def range(self, start: int, end: int) -> PaginatedQuery:
        self.start = start
        self.end = end
        self.calls.append((start, end))
        return self

    def execute(self) -> SimpleNamespace:
        end = min(self.end + 1, self.start + self.max_page_size)
        return SimpleNamespace(data=self.rows[self.start : end])


class PaginatedDatabase:
    def __init__(self, rows: list[dict[str, Any]], *, max_page_size: int = 1_000) -> None:
        self.rows = rows
        self.calls: list[tuple[int, int]] = []
        self.max_page_size = max_page_size

    def table(self, _name: str) -> PaginatedQuery:
        return PaginatedQuery(self.rows, self.calls, self.max_page_size)


def test_plan_schedule_rows_are_paginated() -> None:
    rows = [{"id": str(index)} for index in range(1_001)]
    database = PaginatedDatabase(rows)
    repository = AIPlanRepository(cast(Client, database))

    result = repository.list_schedule_rows(USER_ID)

    assert result == rows
    assert database.calls == [(0, 999), (1_000, 1_999), (1_001, 2_000)]


def test_plan_pagination_handles_a_smaller_server_row_cap() -> None:
    rows = [{"id": str(index)} for index in range(1_001)]
    database = PaginatedDatabase(rows, max_page_size=500)
    repository = AIPlanRepository(cast(Client, database))

    result = repository.list_schedule_rows(USER_ID)

    assert result == rows
    assert database.calls == [
        (0, 999),
        (500, 1_499),
        (1_000, 1_999),
        (1_001, 2_000),
    ]
