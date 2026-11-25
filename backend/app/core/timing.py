"""Request-scoped measurements without user identifiers, tokens or query values."""

import logging
from contextvars import ContextVar
from functools import wraps
from inspect import signature
from time import perf_counter

from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)
metrics = ContextVar("request_metrics", default=None)


def timed(name):
    def decorate(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            start = perf_counter()
            try:
                return fn(*args, **kwargs)
            finally:
                current = metrics.get()
                if current is not None:
                    current[name] = current.get(name, 0.0) + (perf_counter() - start) * 1000

        wrapped.__signature__ = signature(fn, eval_str=True)
        return wrapped

    return decorate


class RequestTimingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        start = perf_counter()
        measurements = {}
        token = metrics.set(measurements)
        try:
            response = await call_next(request)
        finally:
            metrics.reset(token)
        elapsed = (perf_counter() - start) * 1000
        response.headers["Server-Timing"] = ", ".join(
            [f"app;dur={elapsed:.1f}"]
            + [f"{key};dur={value:.1f}" for key, value in measurements.items()]
        )
        route = request.scope.get("route")
        logger.info(
            "request_timing method=%s route=%s status=%s duration_ms=%.1f",
            request.method,
            getattr(route, "path", "unmatched"),
            response.status_code,
            elapsed,
        )
        return response
