"""In-memory stand-in for the supabase-py query builder used by API tests.

Generalized from the fake in test_v1_mobile_execution.py. Supports the subset
of PostgREST operations the repositories use: select, eq, in_, is_, order,
limit, insert, update, delete. Unique keys can be declared per table so that a
duplicate insert raises a PostgREST 23505 error like the real database, and
column defaults can be declared to mirror the schema's DEFAULT clauses.
"""

from __future__ import annotations

from copy import deepcopy
from types import SimpleNamespace
from typing import Any
from uuid import uuid4

from postgrest.exceptions import APIError

Row = dict[str, Any]


def unique_violation(detail: str = "duplicate key value") -> APIError:
    return APIError({"code": "23505", "message": detail, "hint": None, "details": None})


class MemoryQuery:
    def __init__(self, database: MemoryDatabase, table_name: str) -> None:
        self.database = database
        self.table_name = table_name
        self.operation = "select"
        self.filters: list[tuple[str, str]] = []
        self.in_filters: list[tuple[str, set[str]]] = []
        self.null_filters: list[str] = []
        self.values: Row = {}
        self.order_column: str | None = None
        self.descending = False
        self.row_limit: int | None = None
        self.row_range: tuple[int, int] | None = None

    def select(self, _columns: str = "*") -> MemoryQuery:
        return self

    def eq(self, column: str, value: Any) -> MemoryQuery:
        self.filters.append((column, str(value)))
        return self

    def in_(self, column: str, values: list[Any]) -> MemoryQuery:
        self.in_filters.append((column, {str(value) for value in values}))
        return self

    def is_(self, column: str, value: str) -> MemoryQuery:
        assert value == "null"
        self.null_filters.append(column)
        return self

    def order(self, column: str, desc: bool = False) -> MemoryQuery:
        self.order_column = column
        self.descending = desc
        return self

    def limit(self, count: int) -> MemoryQuery:
        self.row_limit = count
        return self

    def range(self, start: int, end: int) -> MemoryQuery:
        self.row_range = (start, end)
        return self

    def insert(self, values: Row) -> MemoryQuery:
        self.operation = "insert"
        self.values = deepcopy(values)
        return self

    def update(self, values: Row) -> MemoryQuery:
        self.operation = "update"
        self.values = deepcopy(values)
        return self

    def delete(self) -> MemoryQuery:
        self.operation = "delete"
        return self

    def execute(self) -> SimpleNamespace:
        rows = self.database.rows.setdefault(self.table_name, [])
        if self.operation == "insert":
            return SimpleNamespace(data=[self._insert(rows)])

        matches = [row for row in rows if self._matches(row)]
        if self.order_column is not None:
            column = self.order_column
            matches.sort(key=lambda row: str(row.get(column, "")), reverse=self.descending)
        if self.row_range is not None:
            start, end = self.row_range
            matches = matches[start : end + 1]
        if self.row_limit is not None:
            matches = matches[: self.row_limit]

        if self.operation == "update":
            for row in matches:
                row.update(self.values)
        elif self.operation == "delete":
            self.database.rows[self.table_name] = [row for row in rows if row not in matches]
        return SimpleNamespace(data=deepcopy(matches))

    def _insert(self, rows: list[Row]) -> Row:
        created = {
            "id": str(uuid4()),
            "created_at": self.database.now,
            **self.database.column_defaults.get(self.table_name, {}),
            **self.values,
        }
        for key_columns in self.database.unique_keys.get(self.table_name, []):
            candidate = tuple(str(created.get(column)) for column in key_columns)
            for existing in rows:
                if tuple(str(existing.get(column)) for column in key_columns) == candidate:
                    raise unique_violation(f"{self.table_name} {key_columns}")
        rows.append(created)
        return deepcopy(created)

    def _matches(self, row: Row) -> bool:
        return (
            all(str(row.get(key)) == value for key, value in self.filters)
            and all(str(row.get(key)) in values for key, values in self.in_filters)
            and all(row.get(key) is None for key in self.null_filters)
        )


class MemoryDatabase:
    def __init__(
        self,
        rows: dict[str, list[Row]] | None = None,
        *,
        unique_keys: dict[str, list[tuple[str, ...]]] | None = None,
        column_defaults: dict[str, Row] | None = None,
        now: str = "2026-09-05T12:00:00+00:00",
    ) -> None:
        """
        `unique_keys` maps table -> unique column tuples (duplicate insert -> 23505).
        `column_defaults` maps table -> values the real schema fills via DEFAULT.
        """
        self.rows: dict[str, list[Row]] = deepcopy(rows) if rows else {}
        self.unique_keys = unique_keys or {}
        self.column_defaults = column_defaults or {}
        self.now = now

    def table(self, table_name: str) -> MemoryQuery:
        return MemoryQuery(self, table_name)
