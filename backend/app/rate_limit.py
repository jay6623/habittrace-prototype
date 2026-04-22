from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
from threading import Lock
from time import time

from fastapi import HTTPException, Request


@dataclass(frozen=True)
class RateLimitSpec:
    requests: int
    window_seconds: int


class InMemoryRateLimiter:
    """
    Simple per-key sliding-window limiter.
    Suitable for single-process deployments and basic abuse prevention.
    """

    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def enforce(self, key: str, spec: RateLimitSpec) -> None:
        now = time()
        window_start = now - spec.window_seconds

        with self._lock:
            q = self._events[key]
            while q and q[0] <= window_start:
                q.popleft()

            if len(q) >= spec.requests:
                retry_after = max(1, int(spec.window_seconds - (now - q[0])))
                raise HTTPException(
                    status_code=429,
                    detail="Rate limit exceeded. Please retry shortly.",
                    headers={"Retry-After": str(retry_after)},
                )

            q.append(now)


rate_limiter = InMemoryRateLimiter()


def get_request_identity(request: Request, user_id: str) -> str:
    if user_id and user_id != "demo-user":
        return f"user:{user_id}"
    client_ip = request.client.host if request.client else "unknown"
    return f"ip:{client_ip}"
