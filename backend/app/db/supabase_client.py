from functools import lru_cache
from urllib.parse import urlsplit, urlunsplit

from supabase import Client, create_client

from ..config import settings


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    """Return a cached Supabase admin client (service_role key)."""
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError(
            "Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env"
        )
    return create_client(_project_url(settings.supabase_url), settings.supabase_service_key)


def is_supabase_configured() -> bool:
    return bool(settings.supabase_url and settings.supabase_service_key)


@lru_cache(maxsize=1)
def get_ai_supabase() -> Client:
    """Return the isolated AI V2 database client (service_role key)."""
    if not settings.ai_supabase_url or not settings.ai_supabase_service_role_key:
        raise RuntimeError(
            "AI Supabase is not configured. Set AI_SUPABASE_URL and "
            "AI_SUPABASE_SERVICE_ROLE_KEY in backend/.env"
        )
    return create_client(
        _project_url(settings.ai_supabase_url),
        settings.ai_supabase_service_role_key,
    )


def is_ai_supabase_configured() -> bool:
    return bool(settings.ai_supabase_url and settings.ai_supabase_service_role_key)


@lru_cache(maxsize=1)
def get_auth_supabase() -> Client:
    """Return a least-privilege client used only to validate bearer tokens."""
    configuration = _auth_configuration()
    if configuration is None:
        raise RuntimeError(
            "Supabase Auth is not configured. Set both AUTH_SUPABASE_URL and "
            "AUTH_SUPABASE_ANON_KEY, or leave both blank and set the existing "
            "SUPABASE_URL and SUPABASE_ANON_KEY, in backend/.env"
        )
    url, anon_key = configuration
    return create_client(url, anon_key)


def is_auth_supabase_configured() -> bool:
    return _auth_configuration() is not None


def _auth_configuration() -> tuple[str, str] | None:
    custom_url = settings.auth_supabase_url.strip()
    custom_anon_key = settings.auth_supabase_anon_key.strip()
    if bool(custom_url) != bool(custom_anon_key):
        return None
    if custom_url and custom_anon_key:
        return _project_url(custom_url), custom_anon_key

    legacy_url = settings.supabase_url.strip()
    legacy_anon_key = settings.supabase_anon_key.strip()
    if legacy_url and legacy_anon_key:
        return _project_url(legacy_url), legacy_anon_key
    return None


def _project_url(value: str) -> str:
    """Accept a Supabase project URL even if `/rest/v1` was copied into it."""
    raw = value.strip().rstrip("/")
    parts = urlsplit(raw)
    path = parts.path
    if path == "/rest/v1":
        path = ""
    return urlunsplit((parts.scheme, parts.netloc, path, "", ""))
