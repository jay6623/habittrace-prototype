from pydantic_settings import BaseSettings
from pathlib import Path
from functools import lru_cache

# Project root is two levels above this file: backend/app/config.py -> backend/ -> project root
_PROJECT_ROOT = Path(__file__).parent.parent.parent


class Settings(BaseSettings):
    # Supabase credentials — set these in backend/.env
    supabase_url: str = ""
    supabase_service_key: str = ""   # service_role key (bypasses RLS, used server-side only)
    supabase_anon_key: str = ""

    # ML artifacts directory — defaults to the sibling model repo
    model_artifacts_dir: str = str(_PROJECT_ROOT / "habittrace_model_dev-main" / "artifacts")
    # Root of the ml Python package (the directory that contains the ml/ folder)
    ml_code_dir: str = str(_PROJECT_ROOT / "habittrace_model_dev-main")

    # CORS origins (comma-separated in .env if needed)
    frontend_url: str = "http://localhost:3000"

    class Config:
        env_file = str(Path(__file__).parent.parent / ".env")
        env_file_encoding = "utf-8"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
