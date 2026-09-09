"""Timezone helpers for V2 plan and outcome data."""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def get_timezone(timezone_name: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone_name)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise ValueError("timezone_name must be a valid IANA timezone") from exc


def as_local(datetime_value: datetime, timezone_name: str) -> datetime:
    if datetime_value.tzinfo is None or datetime_value.utcoffset() is None:
        raise ValueError("datetime values must include a UTC offset")
    return datetime_value.astimezone(get_timezone(timezone_name))
