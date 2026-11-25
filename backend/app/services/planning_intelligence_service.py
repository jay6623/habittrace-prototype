"""Owned plan alternatives, immutable exposure records, and outcome-linked evaluation."""

from __future__ import annotations

import math
from datetime import datetime, time, timedelta, timezone
from uuid import UUID

from fastapi.encoders import jsonable_encoder

from ..core.errors import DomainValidationError, ResourceConflictError, ResourceNotFoundError
from ..repositories.base import BaseRepository
from ..repositories.duration_repository import DurationRepository
from ..schemas.group import GroupPersonalPlanRequest
from ..schemas.planning_intelligence import ComparePlan
from ..services.duration_service import DurationService
from ..utils.timezone import get_timezone

UTC = timezone.utc


class PlanningIntelligenceService(BaseRepository):
    def __init__(self, planner):
        super().__init__(planner.db)
        self.planner = planner

    def _owned(self, user_id, task_id):
        rows = self._execute(
            self.db.table("tasks")
            .select("*")
            .eq("user_id", str(user_id))
            .eq("id", str(task_id))
            .limit(1)
        ).data
        if not rows:
            raise ResourceNotFoundError("Plan not found.")
        return rows[0]

    def _latest(self, user_id, task_id):
        rows = (
            self._execute(
                self.db.table("executions")
                .select("*")
                .eq("user_id", str(user_id))
                .eq("task_id", str(task_id))
                .order("created_at", desc=True)
            ).data
            or []
        )
        return max(rows, key=lambda r: (r.get("created_at", ""), r["id"])) if rows else None

    def _shared(self, user_id, task):
        if task.get("source_group_task_id"):
            shared = (
                self.planner.groups.groups.db.table("group_tasks")
                .select("*")
                .eq("id", task["source_group_task_id"])
                .limit(1)
                .execute()
                .data
            )
            if not shared:
                raise ResourceNotFoundError("Shared task was removed.")
            group_task = self.planner._assigned_task(
                user_id, UUID(shared[0]["group_id"]), UUID(shared[0]["id"])
            )
            return {**group_task, "title": task["title"], "category": task["task_category"]}
        shared = {"title": task["title"], "category": task["task_category"], "priority": "medium"}
        deadline = task.get("ai_plan_details", {}).get("deadline_at")
        if deadline:
            value = datetime.fromisoformat(deadline.replace("Z", "+00:00")).astimezone(UTC)
            shared.update(
                due_date=value.date().isoformat(),
                due_time=value.time().isoformat(),
                due_timezone_name="UTC",
            )
        return shared

    def compare(self, user_id: UUID, body: ComparePlan) -> dict:
        task = self._owned(user_id, body.task_id)
        latest = self._latest(user_id, body.task_id)
        if task["task_status"] == "success":
            raise ResourceConflictError(
                "This plan is complete. There is no remaining work to schedule."
            )
        if latest and latest.get("task_status") is None:
            raise ResourceConflictError("Record the running block before comparing next steps.")
        shared = self._shared(user_id, task)
        duration = DurationService(DurationRepository(self.db)).get(
            user_id,
            task["title"],
            task["task_category"],
            task["planned_duration_min"],
            body.task_id,
        )
        ratio = float((latest or {}).get("completion_ratio") or 0)
        base = duration.median_elapsed_minutes or task["planned_duration_min"]
        continuation = task["task_status"] != "pending"
        remaining = body.remaining_minutes or max(1, math.ceil(base * (1 - ratio)))
        minutes = (
            remaining if continuation or body.remaining_minutes else task["planned_duration_min"]
        )
        tz = get_timezone(task.get("timezone_name") or "UTC")
        now = datetime.now(UTC)
        original = self.planner._task_start(task, str(tz))
        start = original
        if start <= now or continuation:
            local = now.astimezone(tz) + timedelta(minutes=30)
            start = local.replace(minute=(local.minute // 30) * 30, second=0, microsecond=0)
            if start.hour < 8:
                start = start.replace(hour=8, minute=0)
            if start.hour >= 22:
                start = (start + timedelta(days=1)).replace(hour=8, minute=0)
        request = GroupPersonalPlanRequest(
            personal_task_id=body.task_id,
            planned_start=start,
            planned_duration_minutes=minutes,
            timezone_name=str(tz),
            required_energy=task["energy_level"],
            required_focus=task["focus_level"],
            current_energy=body.expected_energy,
            current_focus=body.expected_focus,
        )
        end = datetime.combine(start.astimezone(tz).date() + timedelta(days=8), time.min, tz)
        blocks, warnings = self.planner._blocks(user_id, request, search_end=end)
        profile = self.planner.personalization.build_profile(user_id, exclude_plan_id=body.task_id)
        deadline = self.planner._deadline(shared, str(tz))
        options = []

        def make_option(key, title, description, segments):
            scored = []
            reasons = []
            for index, (instant, length) in enumerate(segments):
                context = list(blocks) + [
                    (
                        a.astimezone(UTC),
                        a.astimezone(UTC) + timedelta(minutes=d),
                        "Another block in this option",
                    )
                    for other, (a, d) in enumerate(segments)
                    if other != index
                ]
                instant = instant.astimezone(UTC)
                local = instant.astimezone(tz)
                conflicts = self.planner._conflicts(instant, length, context)
                if instant <= now:
                    reasons.append("This start time has passed.")
                if conflicts:
                    reasons.append("Overlaps: " + ", ".join(conflicts))
                if deadline and instant + timedelta(minutes=length) > deadline:
                    reasons.append("Finishes after the current group deadline.")
                candidate = request.model_copy(
                    update={"planned_start": instant, "planned_duration_minutes": length}
                )
                plan = self.planner._plan(shared, candidate, context)
                plan["importance"] = task["importance"]
                prediction = None
                if self.planner.model.is_ready:
                    try:
                        prediction = self.planner._score(
                            shared, candidate, context, profile, plan=plan
                        )
                    except (ValueError, TypeError, RuntimeError):
                        if (
                            "Model estimates are unavailable; compare schedule facts instead."
                            not in warnings
                        ):
                            warnings.append(
                                "Model estimates are unavailable; compare schedule facts instead."
                            )
                scored.append(
                    {
                        "planned_start": instant.isoformat(),
                        "duration_minutes": length,
                        "local_date": local.date().isoformat(),
                        "local_time": local.strftime("%H:%M"),
                        "success_probability": prediction["success_probability"]
                        if prediction
                        else None,
                        "daily_minutes": plan["daily_planned_minutes"],
                        "feature_snapshot": plan,
                        "prediction_snapshot": jsonable_encoder(prediction) if prediction else None,
                        "deadline_slack_minutes": int(
                            (deadline - instant - timedelta(minutes=length)).total_seconds() / 60
                        )
                        if deadline
                        else None,
                        "factors": (prediction or {}).get("personalization", {}).get("factors", []),
                        "actions": (prediction or {}).get("recommended_actions", []),
                    }
                )

            options.append(
                {
                    "id": key,
                    "title": title,
                    "description": description,
                    "available": not reasons,
                    "unavailable_reasons": sorted(set(reasons)),
                    "blocks": scored,
                    "total_minutes": sum(length for _, length in segments),
                }
            )

        make_option(
            "current",
            "Keep this work block"
            if not continuation and original > now
            else "Plan the remaining work",
            "Same work scope. No reduction to make the score look better.",
            [(start, minutes)],
        )
        # Search for a complete work block before recommending a move.
        move = None
        for day in range(7):
            for hour in (8, 10, 14, 17, 19):
                slot = datetime.combine(
                    start.astimezone(tz).date() + timedelta(days=day), time(hour), tz
                )
                finish = slot.astimezone(UTC) + timedelta(minutes=minutes)
                if (
                    slot <= now
                    or slot == start
                    or finish > datetime.combine(slot.date(), time(22), tz)
                ):
                    continue
                if deadline and finish > deadline:
                    continue
                if not self.planner._conflicts(slot, minutes, blocks):
                    move = slot
                    break
            if move:
                break
        if move:
            make_option(
                "move",
                "Move to an open time",
                "Preserves the full planned work duration.",
                [(move, minutes)],
            )
        buffer = min(720, max(minutes + 15, math.ceil(minutes * 1.2 / 5) * 5))
        if buffer > minutes:
            make_option(
                "buffer",
                "Give it more time",
                "Same goal, with extra time for uncertainty.",
                [(start, buffer)],
            )
        if minutes >= 20:
            half = minutes // 2
            next_start = start + timedelta(minutes=half + 15)
            remainder = minutes - half
            for offset in range(7 * 48):
                slot = next_start + timedelta(minutes=offset * 30)
                finish = slot.astimezone(UTC) + timedelta(minutes=remainder)
                if slot.hour < 8 or finish > datetime.combine(slot.date(), time(22), tz):
                    continue
                if deadline and finish > deadline:
                    break
                if not self.planner._conflicts(slot, remainder, blocks):
                    next_start = slot
                    break
            # Keep the entire scope; block estimates are not a project-level probability.
            make_option(
                "split",
                "Two shorter blocks",
                "Same total work time, with a break; the second block may move to another day.",
                [(start, half), (next_start, remainder)],
            )
        evidence = {
            "history_samples": profile.sample_count,
            "history_factors": options[0]["blocks"][0]["factors"],
            "duration": duration.model_dump(),
            "progress_ratio": ratio
            if latest and latest.get("completion_ratio") is not None
            else None,
            "remaining_minutes": remaining,
            "remaining_basis": "your_estimate"
            if body.remaining_minutes
            else "reported_progress_and_comparable_duration"
            if duration.available
            else "reported_progress_and_planned_duration",
            "continuation": continuation,
            "shared_source_version": shared.get("updated_at"),
            "expected_energy": body.expected_energy,
            "expected_focus": body.expected_focus,
            "note": "History count describes available evidence, not measured prediction accuracy. "
            "Duration ranges summarize observations, not confidence intervals. "
            "Each score refers to one block; scores are never averaged into task success.",
        }
        snapshot = {k: v for k, v in task.items() if k not in ("prediction", "ai_sync_status")}
        saved = self._execute(
            self.db.table("planning_comparisons").insert(
                {
                    "user_id": str(user_id),
                    "source_task_id": str(body.task_id),
                    "source_snapshot": snapshot,
                    "latest_execution_id": latest["id"] if latest else None,
                    "options": options,
                    "evidence": evidence,
                    "model_version": getattr(self.planner.model, "model_version", None),
                }
            )
        ).data[0]
        return {
            "id": saved["id"],
            "task_title": task["title"],
            "options": options,
            "evidence": evidence,
            "warnings": warnings,
            "timezone_name": str(tz),
        }

    def choose(self, user_id, comparison_id, option_id):
        rows = self._execute(
            self.db.table("planning_comparisons")
            .select("*")
            .eq("id", str(comparison_id))
            .eq("user_id", str(user_id))
            .limit(1)
        ).data
        if not rows:
            raise ResourceNotFoundError("Comparison not found.")
        comparison = rows[0]
        option = next((o for o in comparison["options"] if o["id"] == option_id), None)
        if not option or not option["available"]:
            raise DomainValidationError("Choose an available option.")
        if not comparison.get("selected_option_id"):
            task = self._owned(user_id, comparison["source_task_id"])
            shared = self._shared(user_id, task)
            for block in option["blocks"]:
                req = GroupPersonalPlanRequest(
                    personal_task_id=UUID(task["id"]),
                    planned_start=block["planned_start"],
                    planned_duration_minutes=block["duration_minutes"],
                    timezone_name=task.get("timezone_name") or "UTC",
                )
                self.planner._validate_window(shared, req)
                busy, warnings = self.planner._blocks(user_id, req)
                if warnings:
                    raise ResourceConflictError(
                        "Some calendar items could not be checked. "
                        "Review your calendar and compare again."
                    )
                if self.planner._conflicts(req.planned_start, req.planned_duration_minutes, busy):
                    raise ResourceConflictError(
                        "Your calendar changed. Compare again before applying."
                    )
        result = self._execute(
            self.db.rpc(
                "apply_planning_option",
                {
                    "p_user_id": str(user_id),
                    "p_comparison_id": str(comparison_id),
                    "p_option_id": option_id,
                },
            ),
            conflict_detail="Plan or results changed. Compare again before applying.",
        )
        tasks = result.data or []
        from .task_ai_sync_service import sync_task_ai_safely

        for task in tasks:
            sync_task_ai_safely(self.db, task)
            self.planner.calendar.sync_task_safely(str(user_id), task)
        return {"tasks": tasks, "message": "Plan updated. Recorded outcomes were preserved."}

    def viewed(self, user_id, comparison_id):
        rows = self._execute(
            self.db.table("planning_comparisons")
            .select("id")
            .eq("id", str(comparison_id))
            .eq("user_id", str(user_id))
            .limit(1)
        ).data
        if not rows:
            raise ResourceNotFoundError("Comparison not found.")
        self._execute(
            self.db.table("planning_comparisons")
            .update({"displayed_at": datetime.now(UTC).isoformat()})
            .eq("id", str(comparison_id))
            .eq("user_id", str(user_id))
            .is_("displayed_at", "null")
        )
        return {"recorded": True}

    def evaluation(self, user_id):
        comparisons = (
            self._execute(
                self.db.table("planning_comparisons")
                .select("*")
                .eq("user_id", str(user_id))
                .order("shown_at", desc=True)
                .limit(500)
            ).data
            or []
        )
        outcomes = (
            self._execute(
                self.db.table("executions")
                .select("*")
                .eq("user_id", str(user_id))
                .order("created_at", desc=True)
                .limit(2000)
            ).data
            or []
        )
        latest = {}
        for outcome in outcomes:
            key = outcome.get("ai_plan_input_id")
            if key and outcome.get("task_status") is not None and key not in latest:
                latest[key] = outcome
        pairs = []
        seen_snapshots = set()
        for comparison in comparisons:
            for snap in comparison.get("applied_snapshots") or []:
                result = latest.get(snap.get("plan_input_id"))
                probability = snap.get("probability")
                if (
                    result
                    and probability is not None
                    and snap["plan_input_id"] not in seen_snapshots
                    and comparison.get("selected_at")
                    and result.get("actual_start_time")
                    and result["created_at"] >= comparison["selected_at"]
                    and datetime.fromisoformat(result["actual_start_time"].replace("Z", "+00:00"))
                    >= datetime.fromisoformat(comparison["selected_at"].replace("Z", "+00:00"))
                ):
                    seen_snapshots.add(snap["plan_input_id"])
                    pairs.append(
                        {
                            "date": comparison["shown_at"],
                            "probability": float(probability),
                            "outcome": int(result["task_status"] == "success"),
                            "model_version": comparison.get("model_version") or "unknown",
                        }
                    )
        pairs.sort(key=lambda p: p["date"])

        def metric(rows):
            return {
                "count": len(rows),
                "brier_score": round(
                    sum((p["probability"] - p["outcome"]) ** 2 for p in rows) / len(rows), 4
                )
                if rows
                else None,
            }

        split = len(pairs) // 2
        return {
            "generated": len(comparisons),
            "shown": sum(bool(c.get("displayed_at")) for c in comparisons),
            "selected": sum(bool(c.get("selected_at")) for c in comparisons),
            "evaluated": metric(pairs),
            "by_model": [
                {
                    "model_version": version,
                    **metric([p for p in pairs if p["model_version"] == version]),
                }
                for version in sorted({p["model_version"] for p in pairs})
            ],
            "earlier": metric(pairs[:split]),
            "later": metric(pairs[split:]),
            "note": "Only recorded outcomes linked to the exact applied plan snapshot count. "
            "Lower Brier score means closer estimates; this is not causal evidence that "
            "an option helps. "
            "Partial outcomes count as not fully completed. Missing outcomes or unknown "
            "actual start times are excluded. "
            "Repeated selections of the same plan snapshot count once. "
            "Chronological cohorts may contain different models and task difficulty.",
            "window": (
                "Latest 500 comparisons and 2,000 result records; "
                "chronological halves, not random splits."
            ),
        }
