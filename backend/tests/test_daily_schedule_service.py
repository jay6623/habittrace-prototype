from __future__ import annotations

from copy import deepcopy
from uuid import UUID, uuid4

from app.schemas.daily_schedule import DailyScheduleGenerate
from app.services.daily_schedule_service import DailyScheduleService

from .conftest import USER_ID


class PlansFake:
    def __init__(self, rows=None):
        self.rows = list(rows or [])

    def list_schedule_rows(self, user_id):
        return deepcopy(self.rows)

    def get_owned(self, plan_input_id, user_id):
        return next((row for row in self.rows if str(row.get("id")) == str(plan_input_id)), None)

    def has_child(self, plan_input_id):
        return False

    def create(self, payload):
        row = {
            "id": str(uuid4()),
            "created_at": "2026-09-28T12:00:00+00:00",
            **payload,
        }
        self.rows.append(row)
        return deepcopy(row)


class DraftsFake:
    def __init__(self):
        self.rows = {}

    def create(self, payload):
        row = {
            "id": str(uuid4()),
            "created_at": "2026-09-28T12:00:00+00:00",
            **deepcopy(payload),
        }
        self.rows[row["id"]] = row
        return deepcopy(row)

    def get_owned(self, schedule_id, user_id):
        row = self.rows.get(str(schedule_id))
        if row and str(row["user_id"]) == str(user_id):
            return deepcopy(row)
        return None

    def update(self, schedule_id, user_id, payload):
        row = self.rows[str(schedule_id)]
        row.update(deepcopy(payload))
        return deepcopy(row)


class TasksFake:
    def __init__(self, existing=None):
        self.existing = list(existing or [])
        self.created = []

    def list_for_user(self, user_id, date_filter=None):
        return [
            deepcopy(row)
            for row in self.existing + self.created
            if row["user_id"] == str(user_id)
            and (not date_filter or row["planned_date"] == date_filter)
        ]

    def create(self, user_id, payload):
        row = {
            "id": str(uuid4()),
            "user_id": user_id,
            "created_at": "2026-09-28T12:00:00+00:00",
            "task_status": "pending",
            **deepcopy(payload),
        }
        self.created.append(row)
        return deepcopy(row)


class ModelFake:
    is_ready = True
    model_version = "test"

    def predict(self, plan):
        assert {"id", "input_source", "created_at"} <= plan.keys()
        return {
            "success_probability": 0.8,
            "predicted_failure_reason": "interruption",
        }


class PersonalizationFake:
    def build_profile(self, user_id, **kwargs):
        return object()

    def apply(self, result, plan, profile):
        return {
            **result,
            "personalization": {
                "applied": True,
                "sample_count": 10,
                "confidence": 0.5,
                "history_success_rate": 0.7,
                "factors": [],
            },
        }


class CalendarFake:
    def __init__(self, events=None):
        self.events = list(events or [])
        self.synced = []

    def list_busy_events(self, user_id, start, end):
        return deepcopy(self.events)

    def sync_task_safely(self, user_id, task):
        self.synced.append(task["id"])


def make_service(*, existing=None, calendar_events=None):
    plans = PlansFake()
    drafts = DraftsFake()
    tasks = TasksFake(existing)
    calendar = CalendarFake(calendar_events)
    service = DailyScheduleService(
        plans,
        drafts,
        tasks,
        ModelFake(),
        PersonalizationFake(),
        calendar,
    )
    return service, plans, drafts, tasks, calendar


def request(tasks, **overrides):
    values = {
        "selected_date": "2026-09-28",
        "timezone_name": "UTC",
        "day_start": "08:00",
        "day_end": "14:00",
        "minimum_buffer_minutes": 15,
        "slot_interval_minutes": 15,
        "max_planned_minutes": 480,
        "tasks": tasks,
    }
    values.update(overrides)
    return DailyScheduleGenerate(**values)


def task(title, duration=60, importance=3, **values):
    return {
        "client_id": str(uuid4()),
        "title": title,
        "estimated_duration_minutes": duration,
        "importance": importance,
        "category": "Work",
        **values,
    }


def existing_task(start="09:00", duration=60):
    return {
        "id": str(uuid4()),
        "user_id": str(USER_ID),
        "title": "Existing",
        "planned_start_time": start,
        "planned_date": "2026-09-28",
        "planned_duration_min": duration,
        "focus_level": 3,
        "task_status": "pending",
    }


def test_generation_avoids_conflicts_and_applies_buffer() -> None:
    service, *_ = make_service(existing=[existing_task()])

    result = service.generate(USER_ID, request([task("Deep work", duration=30)]))

    scheduled = result["scheduled_tasks"][0]
    start = scheduled["scheduled_start"]
    assert not start.startswith("2026-09-28T08:45")
    assert not start.startswith("2026-09-28T10:00")
    assert start.startswith("2026-09-28T08:00")


def test_google_calendar_event_is_treated_as_a_fixed_conflict() -> None:
    service, *_ = make_service(
        calendar_events=[
            {
                "start": "2026-09-28T08:00:00+00:00",
                "end": "2026-09-28T09:00:00+00:00",
                "title": "Appointment",
            }
        ]
    )

    result = service.generate(USER_ID, request([task("Write", duration=30)]))

    assert result["scheduled_tasks"][0]["scheduled_start"].startswith("2026-09-28T09:15")


def test_deadline_then_importance_controls_greedy_order() -> None:
    service, *_ = make_service()
    body = request(
        [
            task("Low priority", importance=1),
            task("High priority", importance=5),
            task("Urgent", importance=2, deadline_at="2026-09-28T09:00:00+00:00"),
        ],
        minimum_buffer_minutes=0,
    )

    result = service.generate(USER_ID, body)
    by_title = {item["title"]: item["scheduled_start"] for item in result["scheduled_tasks"]}

    assert by_title["Urgent"].startswith("2026-09-28T08:00")
    assert by_title["High priority"].startswith("2026-09-28T09:00")
    assert by_title["Low priority"].startswith("2026-09-28T10:00")


def test_fixed_event_keeps_its_requested_time() -> None:
    service, *_ = make_service()
    fixed = task(
        "Doctor",
        duration=45,
        is_fixed_time=True,
        fixed_start="2026-09-28T11:00:00+00:00",
    )

    result = service.generate(USER_ID, request([fixed, task("Flexible", duration=60)]))

    doctor = next(item for item in result["scheduled_tasks"] if item["title"] == "Doctor")
    assert doctor["scheduled_start"].startswith("2026-09-28T11:00")
    assert doctor["is_fixed_time"] is True


def test_insufficient_time_returns_clear_unscheduled_reason() -> None:
    service, *_ = make_service()
    body = request(
        [task("One"), task("Two")],
        day_start="08:00",
        day_end="09:00",
        minimum_buffer_minutes=0,
    )

    result = service.generate(USER_ID, body)

    assert len(result["scheduled_tasks"]) == 1
    assert len(result["unscheduled_tasks"]) == 1
    assert "Not enough conflict-free time" in result["unscheduled_tasks"][0]["reason"]


def test_confirmation_creates_tasks_and_ai_plans_only_after_confirmation() -> None:
    service, plans, _drafts, tasks, calendar = make_service()
    draft = service.generate(USER_ID, request([task("Confirm me", duration=30)]))
    assert tasks.created == []

    confirmed = service.confirm(USER_ID, UUID(draft["id"]))

    assert confirmed["status"] == "confirmed"
    assert confirmed["confirmed_at"] is not None
    assert len(tasks.created) == 1
    assert len(plans.rows) == 1
    assert confirmed["scheduled_tasks"][0]["created_task_id"] == tasks.created[0]["id"]
    assert calendar.synced == [tasks.created[0]["id"]]
