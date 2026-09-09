"""
HabitTrace FastAPI backend.

Start with:
    cd backend
    uvicorn app.main:app --reload --port 8000

Behind a reverse proxy (HTTPS), set TRUST_FORWARDED_HEADERS=true and run with
proxy-aware settings (see README).
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from .config import get_cors_allow_origins, get_settings, parse_proxy_trusted_hosts
from .core.errors import register_application_error_handlers
from .routes import (
    account,
    analytics,
    chat,
    executions,
    google_calendar,
    groups,
    health,
    predict,
    tasks,
)
from .routes.v2.router import router as ai_v2_router
from .services.ai_v2_ml_service import get_ai_v2_ml_service
from .services.ml_service import get_ml_service

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load ML models once at startup so the first request is fast
    ml = get_ml_service()
    try:
        ml.load()
    except Exception as exc:
        logger.error("ML model loading failed: %s", exc)
    try:
        get_ai_v2_ml_service().load()
    except Exception as exc:
        logger.error("AI V2 model loading failed: %s", exc)
    yield
    # (shutdown logic could go here)


_app_kwargs: dict = dict(
    title="HabitTrace API",
    description="Habit tracking with ML-powered success prediction",
    version="1.0.0",
    lifespan=lifespan,
)
_rp = settings.api_root_path.strip()
if _rp:
    _app_kwargs["root_path"] = _rp.rstrip("/") or "/"

app = FastAPI(**_app_kwargs)
register_application_error_handlers(app)

# ── CORS (inner) ────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_cors_allow_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Reverse proxy / HTTPS (outer) ───────────────────────────────────────────
if settings.trust_forwarded_headers:
    app.add_middleware(
        ProxyHeadersMiddleware,
        trusted_hosts=parse_proxy_trusted_hosts(settings.proxy_trusted_hosts),
    )

# ── Routers ─────────────────────────────────────────────────────────────────
app.include_router(health.router)
app.include_router(tasks.router, prefix="/tasks", tags=["tasks"])
app.include_router(executions.router, prefix="/executions", tags=["executions"])
app.include_router(predict.router, prefix="/predict", tags=["predict"])
app.include_router(analytics.router, prefix="/analytics", tags=["analytics"])
app.include_router(chat.router, prefix="/chat", tags=["chat"])
app.include_router(
    google_calendar.router,
    prefix="/integrations/google-calendar",
    tags=["integrations"],
)
app.include_router(account.router, prefix="/account", tags=["account"])
app.include_router(groups.router, prefix="/groups", tags=["groups"])
app.include_router(ai_v2_router)
