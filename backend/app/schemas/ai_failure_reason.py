"""Contracts for failure reason definitions and user-confirmed assignments."""

from __future__ import annotations

import re
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

_REASON_CODE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


def _validate_reason_code(value: str) -> str:
    value = value.strip()
    if not _REASON_CODE.fullmatch(value):
        raise ValueError("reason codes must use lowercase letters, numbers, and underscores")
    return value


class FailureReasonCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    primary_reason_code: str = Field(min_length=1, max_length=64)
    secondary_reason_codes: list[str] = Field(default_factory=list, max_length=7)

    @field_validator("primary_reason_code")
    @classmethod
    def validate_primary(cls, value: str) -> str:
        return _validate_reason_code(value)

    @field_validator("secondary_reason_codes")
    @classmethod
    def validate_secondary(cls, values: list[str]) -> list[str]:
        return [_validate_reason_code(value) for value in values]

    @model_validator(mode="after")
    def validate_unique_reasons(self) -> FailureReasonCreate:
        if len(self.secondary_reason_codes) != len(set(self.secondary_reason_codes)):
            raise ValueError("secondary_reason_codes must be unique")
        if self.primary_reason_code in self.secondary_reason_codes:
            raise ValueError("the primary reason cannot also be secondary")
        return self


class FailureReasonDefinitionResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    code: str
    display_name: str
    description: str
    is_active: bool


class FailureReasonSetResponse(BaseModel):
    outcome_id: UUID
    primary_reason_code: str
    secondary_reason_codes: list[str]
    user_confirmed: bool = True
