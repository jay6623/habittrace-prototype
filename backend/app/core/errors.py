"""Sanitized domain errors shared by the V2 API layers."""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse


class ApplicationError(Exception):
    status_code = 500
    code = "application_error"
    default_detail = "The request could not be completed."

    def __init__(self, detail: str | None = None) -> None:
        self.detail = detail or self.default_detail
        super().__init__(self.detail)


class ResourceNotFoundError(ApplicationError):
    status_code = 404
    code = "not_found"
    default_detail = "The requested resource was not found."


class PermissionDeniedError(ApplicationError):
    status_code = 403
    code = "forbidden"
    default_detail = "You do not have permission to perform this action."


class ResourceConflictError(ApplicationError):
    status_code = 409
    code = "conflict"
    default_detail = "The resource conflicts with existing data."


class DomainValidationError(ApplicationError):
    status_code = 422
    code = "invalid_request"
    default_detail = "The request violates a data constraint."


class DatabaseUnavailableError(ApplicationError):
    status_code = 503
    code = "database_unavailable"
    default_detail = "The database is temporarily unavailable."


class RepositoryError(ApplicationError):
    status_code = 500
    code = "repository_error"
    default_detail = "A database operation failed."


def register_application_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApplicationError)
    async def handle_application_error(
        _request: Request, exc: ApplicationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"detail": exc.detail, "code": exc.code},
        )
