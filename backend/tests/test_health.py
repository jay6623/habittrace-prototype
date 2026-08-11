from __future__ import annotations

from fastapi.testclient import TestClient


def test_health_reports_each_supabase_boundary(client: TestClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert {
        "supabase_configured",
        "ai_supabase_configured",
        "auth_supabase_configured",
    }.issubset(response.json())
