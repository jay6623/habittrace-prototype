from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# Project root is two levels above this file: backend/app/config.py -> backend/ -> project root
_PROJECT_ROOT = Path(__file__).parent.parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).parent.parent / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Supabase credentials — set these in backend/.env
    supabase_url: str = ""
    supabase_service_key: str = ""  # service_role key (bypasses RLS, used server-side only)
    supabase_anon_key: str = ""

    # AI V2 data can live in a separate Supabase project. These credentials are
    # backend-only and are never shared with Next.js.
    ai_supabase_url: str = ""
    ai_supabase_service_role_key: str = ""

    # Bearer tokens may come from the existing V1 Auth project or another
    # dedicated Auth project. When blank, the existing Supabase URL/anon key is
    # used for token validation.
    auth_supabase_url: str = ""
    auth_supabase_anon_key: str = ""

    # ML artifacts directory — defaults to the sibling model repo
    model_artifacts_dir: str = str(_PROJECT_ROOT / "habittrace_model_dev-main" / "artifacts")
    # Root of the ml Python package (the directory that contains the ml/ folder)
    ml_code_dir: str = str(_PROJECT_ROOT / "habittrace_model_dev-main")
    # AI V2 package and artifact directory. Override for a real trained model.
    ai_v2_code_dir: str = str(_PROJECT_ROOT / "habittrace_ai_v2")
    ai_v2_artifacts_dir: str = str(
        _PROJECT_ROOT / "habittrace_ai_v2" / "artifacts" / "synthetic"
    )

    # Browser origin for your Next.js app (used for CORS when CORS_ORIGINS is unset)
    frontend_url: str = "http://localhost:3000"
    # Comma-separated list of allowed CORS origins (scheme + host, no path).
    # Example: https://app.example.com,https://www.example.com
    # When set, this list is used as-is (localhost is NOT added automatically).
    cors_origins: str = ""

    # When True, trust forwarded request headers from a reverse proxy.
    trust_forwarded_headers: bool = False
    # Hosts/networks allowed to send them. Use * only behind a known proxy.
    proxy_trusted_hosts: str = "127.0.0.1,::1"

    # If the API is mounted under a sub-path (e.g. https://domain.com/api), set this to /api
    api_root_path: str = ""

    # AI Coach LLM provider. Use "ollama" for local development or "gemini"
    # for the cloud-backed development path.
    llm_provider: str = "ollama"

    # Ollama (AI Coach) — override when the LLM runs on another host in production
    ollama_chat_url: str = "http://localhost:11434/api/chat"
    ollama_model: str = "phi3"

    # Gemini (AI Coach) — backend-only. Never expose GEMINI_API_KEY to Next.js.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.8-flash"
    gemini_max_output_tokens: int = 1_200

    # Basic rate limiting for expensive endpoints (per key, per window)
    rate_limit_window_seconds: int = 60
    predict_requests_per_window: int = 30
    chat_requests_per_window: int = 10


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


def get_cors_allow_origins() -> list[str]:
    """Origins allowed by CORSMiddleware (browser Origin header values)."""
    s = get_settings()
    raw = (s.cors_origins or "").strip()
    if raw:
        return list(dict.fromkeys(x.strip() for x in raw.split(",") if x.strip()))
    return list(
        dict.fromkeys(
            [
                s.frontend_url,
                "http://localhost:3000",
                "http://127.0.0.1:3000",
            ]
        )
    )


def parse_proxy_trusted_hosts(value: str) -> str | list[str]:
    v = (value or "").strip()
    if v == "*":
        return "*"
    parts = [p.strip() for p in v.split(",") if p.strip()]
    return parts if parts else "127.0.0.1"


settings = get_settings()
