from __future__ import annotations

from app.config import settings
from app.db.supabase_client import _project_url, is_auth_supabase_configured


def test_project_url_strips_rest_path() -> None:
    assert _project_url("https://example.supabase.co/rest/v1/") == ("https://example.supabase.co")


def test_partial_custom_auth_configuration_is_rejected(monkeypatch) -> None:
    monkeypatch.setattr(settings, "auth_supabase_url", "https://auth.example.test")
    monkeypatch.setattr(settings, "auth_supabase_anon_key", "")
    monkeypatch.setattr(settings, "supabase_url", "https://legacy.example.test")
    monkeypatch.setattr(settings, "supabase_anon_key", "legacy-anon")

    assert is_auth_supabase_configured() is False


def test_custom_auth_configuration_requires_and_accepts_a_pair(monkeypatch) -> None:
    monkeypatch.setattr(settings, "auth_supabase_url", "https://auth.example.test")
    monkeypatch.setattr(settings, "auth_supabase_anon_key", "auth-anon")

    assert is_auth_supabase_configured() is True
