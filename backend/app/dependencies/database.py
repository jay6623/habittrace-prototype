"""Database dependency for API routes."""
from fastapi import HTTPException, status
from supabase import Client

from ..db.supabase_client import (
    get_ai_supabase,
    get_auth_supabase,
    is_ai_supabase_configured,
    is_auth_supabase_configured,
)


def get_ai_database() -> Client:
    if not is_ai_supabase_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI database is not configured.",
        )
    return get_ai_supabase()


def get_auth_database() -> Client:
    if not is_auth_supabase_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is not configured.",
        )
    return get_auth_supabase()
