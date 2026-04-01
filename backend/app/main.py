"""
HabitTrace FastAPI backend.

Start with:
    cd backend
    uvicorn app.main:app --reload --port 8000
"""
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import settings
from .services.ml_service import get_ml_service
from .routes import health, tasks, executions, predict, analytics, chat

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load ML models once at startup so the first request is fast
    ml = get_ml_service()
    try:
        ml.load()
    except Exception as exc:
        logger.error("ML model loading failed: %s", exc)
    yield
    # (shutdown logic could go here)


app = FastAPI(
    title="HabitTrace API",
    description="Habit tracking with ML-powered success prediction",
    version="1.0.0",
    lifespan=lifespan,
)

# ── CORS ─────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        settings.frontend_url,
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(health.router)
app.include_router(tasks.router,      prefix="/tasks",      tags=["tasks"])
app.include_router(executions.router, prefix="/executions", tags=["executions"])
app.include_router(predict.router,    prefix="/predict",    tags=["predict"])
app.include_router(analytics.router,  prefix="/analytics",  tags=["analytics"])
app.include_router(chat.router,       prefix="/chat",        tags=["chat"])
