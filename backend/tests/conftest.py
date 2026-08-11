from __future__ import annotations

from collections.abc import Iterator
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.dependencies.auth import get_current_user_id
from app.main import app

USER_ID = UUID("11111111-1111-4111-8111-111111111111")
PLAN_ID = UUID("22222222-2222-4222-8222-222222222222")
OUTCOME_ID = UUID("33333333-3333-4333-8333-333333333333")


@pytest.fixture
def client() -> Iterator[TestClient]:
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def authenticated_client(client: TestClient) -> TestClient:
    app.dependency_overrides[get_current_user_id] = lambda: USER_ID
    return client
