from __future__ import annotations

from datetime import date
from uuid import UUID

from app.schemas.coach_tools import GenerateDailyScheduleArgs, ToolCall
from app.services.coach_tool_registry import CoachToolRegistry
from app.services.coaching_daily_schedule_service import CoachingDailyScheduleService

USER_ID = "11111111-1111-4111-8111-111111111111"


class ContextFake:
    def get_preferences(self, user_id, timezone_name):
        return {
            "preferred_day_start": "07:30",
            "preferred_day_end": "21:00",
            "minimum_buffer_minutes": 10,
        }


class DailyScheduleFake:
    def __init__(self):
        self.user_id = None
        self.body = None

    def generate(self, user_id, body):
        self.user_id = user_id
        self.body = body
        return {
            "id": "22222222-2222-4222-8222-222222222222",
            "user_id": str(user_id),
            "selected_date": body.selected_date.isoformat(),
            "status": "draft",
            "scheduled_tasks": [
                {
                    "task_id": str(body.tasks[0].client_id),
                    "title": body.tasks[0].title,
                }
            ],
            "unscheduled_tasks": [],
        }


def test_coach_generates_reviewable_daily_schedule_draft_from_multiple_tasks() -> None:
    generator = DailyScheduleFake()
    adapter = CoachingDailyScheduleService(ContextFake(), generator)
    registry = CoachToolRegistry(ContextFake(), daily_schedule_service=adapter)
    selected_date = date(2026, 10, 1)

    result = registry.execute(
        ToolCall(
            name="generate_daily_schedule",
            arguments={
                "selected_date": selected_date.isoformat(),
                "tasks": [
                    {
                        "title": "Write report",
                        "category": "Work",
                        "estimated_duration_minutes": 60,
                        "importance": 5,
                    },
                    {
                        "title": "Go to the gym",
                        "category": "Fitness/Health",
                        "estimated_duration_minutes": 45,
                    },
                ],
            },
        ),
        user_id=USER_ID,
        timezone_name="America/Denver",
    )

    assert result.ok is True
    assert result.proposal is not None
    assert result.proposal["kind"] == "daily_schedule"
    assert result.data == {
        "status": "draft_created",
        "schedule_id": "22222222-2222-4222-8222-222222222222",
        "selected_date": selected_date.isoformat(),
        "scheduled_count": 1,
        "unscheduled_count": 0,
        "confirmation_required": True,
    }
    assert generator.user_id == UUID(USER_ID)
    assert generator.body.day_start.isoformat() == "07:30:00"
    assert generator.body.day_end.isoformat() == "21:00:00"
    assert generator.body.minimum_buffer_minutes == 10
    assert [task.category for task in generator.body.tasks] == [
        "Work",
        "Fitness/Health",
    ]


def test_coach_preserves_deadline_and_fixed_time_in_user_timezone() -> None:
    generator = DailyScheduleFake()
    adapter = CoachingDailyScheduleService(ContextFake(), generator)

    adapter.generate(
        USER_ID,
        GenerateDailyScheduleArgs.model_validate(
            {
                "selected_date": "2026-10-01",
                "tasks": [
                    {
                        "title": "Appointment",
                        "category": "Errands/Admin",
                        "estimated_duration_minutes": 30,
                        "deadline_time": "15:00",
                        "fixed_start_time": "14:00",
                    }
                ],
            }
        ),
        timezone_name="America/Denver",
    )

    task = generator.body.tasks[0]
    assert task.is_fixed_time is True
    assert task.fixed_start.isoformat() == "2026-10-01T14:00:00-06:00"
    assert task.deadline_at.isoformat() == "2026-10-01T15:00:00-06:00"
