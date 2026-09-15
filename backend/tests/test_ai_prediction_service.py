from __future__ import annotations

from app.services.ai_prediction_service import AIPredictionService

from .conftest import PLAN_ID, USER_ID
from .factories import plan_row


class PlanRepositoryFake:
    def get_owned(self, plan_input_id, user_id):
        return plan_row(id=str(plan_input_id), user_id=str(user_id))


class PredictionRepositoryFake:
    def __init__(self, *, version: str | None = None) -> None:
        self.created_success: list[dict] = []
        self.created_failure: list[dict] = []
        self.success = None
        self.failure = None
        self.models = {
            "success": {"id": f"success-model-{version}", "version": version},
            "failure_reason": {"id": f"failure-model-{version}", "version": version},
        }
        if version is not None:
            self.success = {
                "id": "saved-success",
                "model_version_id": f"success-model-{version}",
                "success_probability": 0.7,
                "explanation_snapshot": {},
            }
            self.failure = {
                "id": "saved-failure",
                "model_version_id": f"failure-model-{version}",
                "reason_probabilities": {"low_readiness": 0.2},
                "explanation_snapshot": {"predicted_failure_reason": "low_readiness"},
            }

    def get_latest_success_prediction(self, plan_input_id):
        return self.success

    def get_latest_failure_prediction(self, success_prediction_id):
        return self.failure

    def get_model_version_by_id(self, model_version_id):
        for model in self.models.values():
            if model["id"] == model_version_id:
                return model
        if model_version_id.startswith("success-model-"):
            return {
                "id": model_version_id,
                "version": model_version_id.removeprefix("success-model-"),
            }
        return {
            "id": model_version_id,
            "version": model_version_id.removeprefix("failure-model-"),
        }

    def get_model_version(self, model_type, version):
        model = self.models[model_type]
        return model if model["version"] == version else None

    def create_model_version(self, payload):
        model = {
            "id": f'{payload["model_type"]}-model-{payload["version"]}',
            **payload,
        }
        self.models[payload["model_type"]] = model
        return model

    def create_success_prediction(self, payload):
        self.created_success.append(payload)
        return {"id": "new-success", **payload}

    def create_failure_prediction(self, payload):
        self.created_failure.append(payload)
        return {"id": "new-failure", **payload}


class ModelServiceFake:
    is_ready = True

    def __init__(self, version: str) -> None:
        self.model_version = version
        self.calls = 0

    def predict(self, plan):
        self.calls += 1
        return {
            "success_probability": 0.6,
            "failure_reason_probabilities": {"low_readiness": 0.3},
            "predicted_failure_reason": "low_readiness",
            "explanation": {"recommended_actions": []},
            "recommended_actions": [],
        }


class PersonalizationFake:
    def build_profile(self, user_id, *, exclude_plan_id=None):
        return {}

    def apply(self, result, plan, profile):
        return {
            **result,
            "base_success_probability": result["success_probability"],
            "personalization": {
                "applied": False,
                "sample_count": 0,
                "confidence": 0.0,
                "history_success_rate": None,
                "factors": [],
            },
        }


def build_service(repository, model):
    return AIPredictionService(
        PlanRepositoryFake(), repository, model, PersonalizationFake()
    )


def test_predict_for_plan_reuses_complete_prediction_for_current_model() -> None:
    repository = PredictionRepositoryFake(version="model-1")
    model = ModelServiceFake("model-1")

    result = build_service(repository, model).predict_for_plan(USER_ID, PLAN_ID)

    assert result["success_prediction_id"] == "saved-success"
    assert model.calls == 0
    assert repository.created_success == []
    assert repository.created_failure == []


def test_predict_for_plan_creates_prediction_when_model_version_changes() -> None:
    repository = PredictionRepositoryFake(version="model-1")
    model = ModelServiceFake("model-2")

    result = build_service(repository, model).predict_for_plan(USER_ID, PLAN_ID)

    assert result["success_prediction_id"] == "new-success"
    assert result["failure_prediction_id"] == "new-failure"
    assert model.calls == 1
    assert len(repository.created_success) == 1
    assert len(repository.created_failure) == 1


def test_latest_for_plan_hides_prediction_from_old_model_version() -> None:
    repository = PredictionRepositoryFake(version="model-1")
    model = ModelServiceFake("model-2")

    result = build_service(repository, model).latest_for_plan(USER_ID, PLAN_ID)

    assert result is None
