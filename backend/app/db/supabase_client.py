from functools import lru_cache
from supabase import create_client, Client
from ..config import settings


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    """Return a cached Supabase admin client (service_role key)."""
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError(
            "Supabase is not configured. "
            "Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env"
        )
    return create_client(settings.supabase_url, settings.supabase_service_key)


def is_supabase_configured() -> bool:
    return bool(settings.supabase_url and settings.supabase_service_key)
