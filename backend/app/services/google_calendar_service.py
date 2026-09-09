"""Google Calendar OAuth token storage and one-way task synchronization."""

from __future__ import annotations

import base64
import hashlib
import logging
from datetime import datetime, timedelta, timezone
from urllib.parse import quote
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from cryptography.fernet import Fernet, InvalidToken
from supabase import Client

from ..config import Settings, settings

logger = logging.getLogger(__name__)

GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3"
_HTTP_CLIENT = httpx.Client(timeout=15.0)


class GoogleCalendarError(RuntimeError):
    """A safe error that can be returned by the integration API."""


class GoogleCalendarService:
    def __init__(
        self,
        db: Client,
        app_settings: Settings = settings,
        http_client: httpx.Client | None = None,
    ) -> None:
        self.db = db
        self.settings = app_settings
        self.http = http_client or _HTTP_CLIENT

    @property
    def configured(self) -> bool:
        return bool(
            self.settings.google_oauth_client_id
            and self.settings.google_oauth_client_secret
            and len(self.settings.google_token_encryption_key) >= 32
        )

    def status(self, user_id: str) -> dict:
        connection = self._get_connection(user_id) if self.configured else None
        return {
            "configured": self.configured,
            "connected": connection is not None,
            "timezone": connection.get("timezone") if connection else None,
            "last_synced_at": connection.get("last_synced_at") if connection else None,
            "last_error": connection.get("last_error") if connection else None,
        }

    def connect(
        self,
        user_id: str,
        provider_token: str,
        provider_refresh_token: str | None,
        timezone_name: str,
    ) -> dict:
        self._require_configured()
        self._validate_timezone(timezone_name)
        current = self._get_connection(user_id)
        refresh_token = provider_refresh_token
        if not refresh_token and current:
            refresh_token = self._decrypt(current["refresh_token_encrypted"])
        if not refresh_token:
            raise GoogleCalendarError(
                "Google did not return a refresh token. Disconnect Calendar access "
                "from your Google Account and connect again."
            )

        self._validate_access_token(provider_token)
        now = datetime.now(timezone.utc)
        row = {
            "user_id": user_id,
            "provider": "google",
            "calendar_id": "primary",
            "timezone": timezone_name,
            "access_token_encrypted": self._encrypt(provider_token),
            "refresh_token_encrypted": self._encrypt(refresh_token),
            "token_expires_at": (now + timedelta(minutes=50)).isoformat(),
            "last_error": None,
            "updated_at": now.isoformat(),
        }
        result = (
            self.db.table("calendar_connections")
            .upsert(row, on_conflict="user_id,provider")
            .execute()
        )
        if not result.data:
            raise GoogleCalendarError("Calendar connection could not be saved.")
        return result.data[0]

    def disconnect(self, user_id: str) -> None:
        self.db.table("calendar_event_links").delete().eq("user_id", user_id).execute()
        self.db.table("calendar_connections").delete().eq("user_id", user_id).eq(
            "provider", "google"
        ).execute()

    def sync_all(self, user_id: str) -> dict:
        connection = self._require_connection(user_id)
        tasks = (
            self.db.table("tasks")
            .select("*")
            .eq("user_id", user_id)
            .gte(
                "planned_date",
                datetime.now(ZoneInfo(connection["timezone"])).date().isoformat(),
            )
            .order("planned_date")
            .execute()
            .data
        )
        synced = 0
        errors: list[str] = []
        for task in tasks:
            try:
                connection = self._upsert_task(connection, task)
                synced += 1
            except GoogleCalendarError as exc:
                errors.append(f"{task.get('title', 'Task')}: {exc}")

        now = datetime.now(timezone.utc).isoformat()
        last_error = errors[0] if errors else None
        self._update_connection(user_id, last_synced_at=now, last_error=last_error)
        return {"synced": synced, "failed": len(errors), "errors": errors[:10]}

    def sync_task_safely(self, user_id: str, task: dict) -> None:
        if not self.configured:
            return
        connection = self._get_connection(user_id)
        if not connection:
            return
        try:
            self._upsert_task(connection, task)
            self._update_connection(user_id, last_error=None)
        except Exception as exc:  # Calendar downtime must not break task CRUD.
            message = str(exc) if isinstance(exc, GoogleCalendarError) else "Calendar sync failed."
            logger.warning("Google Calendar task sync failed for user %s: %s", user_id, exc)
            self._update_connection(user_id, last_error=message)

    def delete_task_safely(self, user_id: str, task_id: str) -> None:
        if not self.configured:
            return
        connection = self._get_connection(user_id)
        if not connection:
            return
        link = self._get_link(user_id, task_id)
        if not link:
            return
        try:
            event_id = quote(str(link["google_event_id"]), safe="")
            response, connection = self._calendar_request(
                connection,
                "DELETE",
                f"/calendars/primary/events/{event_id}",
            )
            if response.status_code not in (204, 404):
                self._raise_google_error(response)
            self.db.table("calendar_event_links").delete().eq("user_id", user_id).eq(
                "task_id", task_id
            ).execute()
            self._update_connection(user_id, last_error=None)
        except Exception as exc:
            message = str(exc) if isinstance(exc, GoogleCalendarError) else "Calendar sync failed."
            logger.warning("Google Calendar delete sync failed for user %s: %s", user_id, exc)
            self._update_connection(user_id, last_error=message)

    def _upsert_task(self, connection: dict, task: dict) -> dict:
        event = self._event_from_task(task, connection["timezone"])
        link = self._get_link(str(task["user_id"]), str(task["id"]))
        google_event_id: str | None = None
        if link:
            event_id = quote(str(link["google_event_id"]), safe="")
            response, connection = self._calendar_request(
                connection,
                "PUT",
                f"/calendars/primary/events/{event_id}",
                json=event,
            )
            if response.status_code == 404:
                link = None
            elif response.status_code >= 400:
                self._raise_google_error(response)
            else:
                google_event_id = str(link["google_event_id"])

        if not link:
            task_marker = quote(f"habittraceTaskId={task['id']}", safe="")
            lookup, connection = self._calendar_request(
                connection,
                "GET",
                "/calendars/primary/events"
                f"?privateExtendedProperty={task_marker}&maxResults=1&singleEvents=true",
            )
            if lookup.status_code >= 400:
                self._raise_google_error(lookup)
            items = lookup.json().get("items", [])
            if items:
                google_event_id = str(items[0]["id"])
                event_id = quote(google_event_id, safe="")
                response, connection = self._calendar_request(
                    connection,
                    "PUT",
                    f"/calendars/primary/events/{event_id}",
                    json=event,
                )
            else:
                response, connection = self._calendar_request(
                    connection, "POST", "/calendars/primary/events", json=event
                )
            if response.status_code >= 400:
                self._raise_google_error(response)
            google_event_id = google_event_id or str(response.json()["id"])

        row = {
            "user_id": str(task["user_id"]),
            "task_id": str(task["id"]),
            "calendar_id": "primary",
            "google_event_id": google_event_id,
            "last_synced_at": datetime.now(timezone.utc).isoformat(),
        }
        self.db.table("calendar_event_links").upsert(row, on_conflict="user_id,task_id").execute()
        return connection

    def _event_from_task(self, task: dict, timezone_name: str) -> dict:
        try:
            planned_date = datetime.strptime(str(task["planned_date"]), "%Y-%m-%d").date()
            raw_time = str(task["planned_start_time"]).strip().upper()
            parsed_time = None
            for pattern in ("%I:%M %p", "%H:%M", "%H:%M:%S"):
                try:
                    parsed_time = datetime.strptime(raw_time, pattern).time()
                    break
                except ValueError:
                    continue
            if parsed_time is None:
                raise ValueError("unsupported time")
            start = datetime.combine(planned_date, parsed_time)
            end = start + timedelta(minutes=int(task["planned_duration_min"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise GoogleCalendarError("The task has an invalid date or start time.") from exc

        return {
            "summary": str(task["title"]),
            "description": "Synced from HabitTrace",
            "start": {"dateTime": start.isoformat(), "timeZone": timezone_name},
            "end": {"dateTime": end.isoformat(), "timeZone": timezone_name},
            "extendedProperties": {"private": {"habittraceTaskId": str(task["id"])}},
        }

    def _calendar_request(
        self, connection: dict, method: str, path: str, json: dict | None = None
    ) -> tuple[httpx.Response, dict]:
        token, connection = self._valid_access_token(connection)
        try:
            response = self.http.request(
                method,
                f"{GOOGLE_CALENDAR_API}{path}",
                headers={"Authorization": f"Bearer {token}"},
                json=json,
            )
        except httpx.HTTPError as exc:
            raise GoogleCalendarError("Google Calendar is temporarily unavailable.") from exc
        if response.status_code == 401:
            token, connection = self._refresh_access_token(connection)
            try:
                response = self.http.request(
                    method,
                    f"{GOOGLE_CALENDAR_API}{path}",
                    headers={"Authorization": f"Bearer {token}"},
                    json=json,
                )
            except httpx.HTTPError as exc:
                raise GoogleCalendarError("Google Calendar is temporarily unavailable.") from exc
        return response, connection

    def _valid_access_token(self, connection: dict) -> tuple[str, dict]:
        expires_at = self._parse_datetime(connection.get("token_expires_at"))
        if expires_at and expires_at > datetime.now(timezone.utc) + timedelta(seconds=60):
            return self._decrypt(connection["access_token_encrypted"]), connection
        return self._refresh_access_token(connection)

    def _refresh_access_token(self, connection: dict) -> tuple[str, dict]:
        refresh_token = self._decrypt(connection["refresh_token_encrypted"])
        try:
            response = self.http.post(
                GOOGLE_TOKEN_URL,
                data={
                    "client_id": self.settings.google_oauth_client_id,
                    "client_secret": self.settings.google_oauth_client_secret,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                },
            )
        except httpx.HTTPError as exc:
            raise GoogleCalendarError("Google authorization is unavailable.") from exc
        if response.status_code >= 400:
            raise GoogleCalendarError("Google authorization expired. Please reconnect Calendar.")
        payload = response.json()
        access_token = payload.get("access_token")
        if not access_token:
            raise GoogleCalendarError("Google did not return a usable access token.")
        expires_at = datetime.now(timezone.utc) + timedelta(
            seconds=max(int(payload.get("expires_in", 3600)) - 60, 60)
        )
        updates = {
            "access_token_encrypted": self._encrypt(access_token),
            "token_expires_at": expires_at.isoformat(),
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        if payload.get("refresh_token"):
            updates["refresh_token_encrypted"] = self._encrypt(payload["refresh_token"])
        self.db.table("calendar_connections").update(updates).eq("id", connection["id"]).execute()
        return access_token, {**connection, **updates}

    def _validate_access_token(self, token: str) -> None:
        try:
            response = self.http.get(
                f"{GOOGLE_CALENDAR_API}/calendars/primary/events",
                headers={"Authorization": f"Bearer {token}"},
                params={"maxResults": 1, "singleEvents": "true"},
            )
        except httpx.HTTPError as exc:
            raise GoogleCalendarError("Google Calendar is temporarily unavailable.") from exc
        if response.status_code >= 400:
            self._raise_google_error(response)

    @staticmethod
    def _raise_google_error(response: httpx.Response) -> None:
        if response.status_code in (401, 403):
            raise GoogleCalendarError(
                "Google Calendar permission is missing or expired. Please reconnect."
            )
        if response.status_code == 429:
            raise GoogleCalendarError("Google Calendar quota was reached. Try again later.")
        raise GoogleCalendarError("Google Calendar is temporarily unavailable.")

    def _get_connection(self, user_id: str) -> dict | None:
        result = (
            self.db.table("calendar_connections")
            .select("*")
            .eq("user_id", user_id)
            .eq("provider", "google")
            .limit(1)
            .execute()
        )
        return result.data[0] if result.data else None

    def _require_connection(self, user_id: str) -> dict:
        self._require_configured()
        connection = self._get_connection(user_id)
        if not connection:
            raise GoogleCalendarError("Google Calendar is not connected.")
        return connection

    def _get_link(self, user_id: str, task_id: str) -> dict | None:
        result = (
            self.db.table("calendar_event_links")
            .select("*")
            .eq("user_id", user_id)
            .eq("task_id", task_id)
            .limit(1)
            .execute()
        )
        return result.data[0] if result.data else None

    def _update_connection(self, user_id: str, **values: object) -> None:
        self.db.table("calendar_connections").update(
            {**values, "updated_at": datetime.now(timezone.utc).isoformat()}
        ).eq("user_id", user_id).eq("provider", "google").execute()

    def _require_configured(self) -> None:
        if not self.configured:
            raise GoogleCalendarError("Google Calendar is not configured on the backend.")

    @staticmethod
    def _validate_timezone(value: str) -> None:
        try:
            ZoneInfo(value)
        except ZoneInfoNotFoundError as exc:
            raise GoogleCalendarError("Invalid browser time zone.") from exc

    @staticmethod
    def _parse_datetime(value: object) -> datetime | None:
        if not value:
            return None
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            return None

    def _fernet(self) -> Fernet:
        secret = self.settings.google_token_encryption_key.encode("utf-8")
        key = base64.urlsafe_b64encode(hashlib.sha256(secret).digest())
        return Fernet(key)

    def _encrypt(self, value: str) -> str:
        return self._fernet().encrypt(value.encode("utf-8")).decode("ascii")

    def _decrypt(self, value: str) -> str:
        try:
            return self._fernet().decrypt(value.encode("ascii")).decode("utf-8")
        except (InvalidToken, ValueError) as exc:
            raise GoogleCalendarError(
                "Stored Google credentials cannot be read. Please reconnect Calendar."
            ) from exc
