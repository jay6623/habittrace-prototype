from pydantic import BaseModel, Field


class GoogleCalendarConnect(BaseModel):
    provider_token: str = Field(..., min_length=1)
    provider_refresh_token: str | None = None
    timezone: str = Field(default="UTC", min_length=1, max_length=100)


class GoogleCalendarStatus(BaseModel):
    configured: bool
    connected: bool
    timezone: str | None = None
    last_synced_at: str | None = None
    last_error: str | None = None


class GoogleCalendarSyncResult(BaseModel):
    synced: int
    failed: int
    errors: list[str]


class GoogleCalendarConnectResult(BaseModel):
    status: GoogleCalendarStatus
    sync: GoogleCalendarSyncResult
