"""Supabase access for AI model versions and prediction records."""

from __future__ import annotations

from .base import BaseRepository


class AIPredictionRepository(BaseRepository):
    def get_model_version(self, model_type: str, version: str) -> dict | None:
        response = self._execute(
            self.db.table("ai_model_versions")
            .select("*")
            .eq("model_type", model_type)
            .eq("version", version)
            .limit(1)
        )
        return response.data[0] if response.data else None

    def create_model_version(self, payload: dict) -> dict:
        response = self._execute(
            self.db.table("ai_model_versions").insert(payload),
            conflict_detail="This AI model version already exists.",
        )
        if not response.data:
            raise RuntimeError("The database did not return the created model version.")
        return response.data[0]

    def create_success_prediction(self, payload: dict) -> dict:
        response = self._execute(self.db.table("ai_success_predictions").insert(payload))
        if not response.data:
            raise RuntimeError("The database did not return the success prediction.")
        return response.data[0]

    def create_failure_prediction(self, payload: dict) -> dict:
        response = self._execute(self.db.table("ai_failure_predictions").insert(payload))
        if not response.data:
            raise RuntimeError("The database did not return the failure prediction.")
        return response.data[0]

    def get_latest_success_prediction(self, plan_input_id: str) -> dict | None:
        response = self._execute(
            self.db.table("ai_success_predictions")
            .select("*")
            .eq("plan_input_id", plan_input_id)
            .order("predicted_at", desc=True)
            .limit(1)
        )
        return response.data[0] if response.data else None

    def get_latest_failure_prediction(self, success_prediction_id: str) -> dict | None:
        response = self._execute(
            self.db.table("ai_failure_predictions")
            .select("*")
            .eq("success_prediction_id", success_prediction_id)
            .order("predicted_at", desc=True)
            .limit(1)
        )
        return response.data[0] if response.data else None

    def get_model_version_by_id(self, model_version_id: str) -> dict | None:
        response = self._execute(
            self.db.table("ai_model_versions").select("*").eq("id", model_version_id).limit(1)
        )
        return response.data[0] if response.data else None
