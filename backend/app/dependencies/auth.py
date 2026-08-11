"""Strict Supabase bearer authentication for V2 endpoints."""
from __future__ import annotations

from typing import Annotated
from uuid import UUID

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import Client
from supabase_auth.errors import AuthApiError, AuthError, AuthRetryableError

from .database import get_auth_database

_bearer = HTTPBearer(auto_error=False)


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="A valid Supabase access token is required.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def get_current_user_id(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    db: Annotated[Client, Depends(get_auth_database)],
) -> UUID:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized()

    try:
        response = db.auth.get_user(credentials.credentials)
    except AuthRetryableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is temporarily unavailable.",
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is temporarily unavailable.",
        ) from exc
    except AuthApiError as exc:
        if exc.status == status.HTTP_429_TOO_MANY_REQUESTS or exc.status >= 500:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Authentication service is temporarily unavailable.",
            ) from exc
        raise _unauthorized() from exc
    except (ValueError, TypeError) as exc:
        raise _unauthorized() from exc
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is temporarily unavailable.",
        ) from exc
    except Exception as exc:
        # Supabase auth client versions do not expose one stable base exception.
        # Keep the response sanitized and never include the token or SDK message.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service is temporarily unavailable.",
        ) from exc

    user = getattr(response, "user", None)
    user_id = getattr(user, "id", None)
    if not user_id:
        raise _unauthorized()

    try:
        return UUID(str(user_id))
    except (ValueError, TypeError, AttributeError) as exc:
        raise _unauthorized() from exc


CurrentUserId = Annotated[UUID, Depends(get_current_user_id)]
