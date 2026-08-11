from __future__ import annotations

import pandas as pd

from habittrace_ai.export_db import _quality_report, _rest_url


def test_rest_url_accepts_project_or_rest_url() -> None:
    assert _rest_url("https://example.supabase.co") == "https://example.supabase.co/rest/v1"
    assert _rest_url("https://example.supabase.co/rest/v1/") == (
        "https://example.supabase.co/rest/v1"
    )


def test_quality_report_fails_closed_for_empty_snapshot() -> None:
    report = _quality_report(pd.DataFrame(), pd.DataFrame(), pd.DataFrame())
    assert report["valid"] is False
    assert report["success_examples"] == 0
