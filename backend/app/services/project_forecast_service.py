"""Rule-based shared project forecasts; never reads personal schedules or model scores."""

from datetime import datetime, time, timedelta, timezone
from uuid import UUID

from ..core.errors import DomainValidationError, PermissionDeniedError, ResourceNotFoundError
from ..repositories.base import BaseRepository
from ..utils.timezone import get_timezone

UTC = timezone.utc


class ProjectForecastService(BaseRepository):
    def __init__(self, groups):
        super().__init__(groups.groups.db)
        self.groups = groups

    def _rows(self, table, group_id):
        return (
            self._execute(self.db.table(table).select("*").eq("group_id", str(group_id))).data or []
        )

    def forecast(self, user_id, group_id, timezone_name="UTC", now=None):
        self.groups._require_member(group_id, user_id)
        group = self.groups.groups.get_group(str(group_id)) or {}
        timezone_name = group.get("planning_timezone_name") or "UTC"
        zone = get_timezone(timezone_name)
        now = (now or datetime.now(UTC)).astimezone(zone)
        tasks = {t["id"]: t for t in self._rows("group_tasks", group_id)}
        members = {m["user_id"]: m for m in self._rows("group_members", group_id)}
        profiles = self.groups.groups.get_profiles(list(members))
        assignments = self._rows("group_task_assignees", group_id)
        by_task = {
            key: [a for a in assignments if a["task_id"] == key and a["user_id"] in members]
            for key in tasks
        }
        edges = self._rows("group_task_dependencies", group_id)
        predecessors = {
            key: [
                e["predecessor_id"]
                for e in edges
                if e["task_id"] == key and e["predecessor_id"] in tasks
            ]
            for key in tasks
        }
        completed = {
            key: bool(by_task[key]) and all(a.get("outcome") == "success" for a in by_task[key])
            for key in tasks
        }
        done = set()
        ordered = []
        while len(ordered) < len(tasks):
            ready = sorted(
                (
                    key
                    for key in tasks
                    if key not in done and all(p in done for p in predecessors[key])
                ),
                key=lambda k: (tasks[k].get("due_date") or "9999", tasks[k]["title"]),
            )
            if not ready:
                raise DomainValidationError(
                    "Project dependencies contain a cycle. Remove a dependency first."
                )
            ordered.extend(ready)
            done.update(ready)
        forecasts = {}
        member_end = {key: now for key in members}
        used = {}
        workload = {key: 0 for key in members}
        unknown_work = {key: False for key in members}

        def allocate(member_id, after, minutes):
            if minutes <= 0:
                return after
            capacity = members[member_id].get("shared_minutes_per_day")
            until = members[member_id].get("capacity_until")
            if capacity is None or capacity == 0:
                return None
            if (
                not until
            ):  # Time-bounded consent avoids treating an old capacity as indefinitely available.
                return None
            cursor = max(after, member_end[member_id])
            remaining = minutes
            for _ in range(366):
                if cursor.date().isoformat() > str(until):
                    return None
                start = datetime.combine(cursor.date(), time(8), zone)
                stop = datetime.combine(cursor.date(), time(22), zone)
                cursor = max(cursor, start)
                key = (member_id, cursor.date())
                free = min(
                    capacity - used.get(key, 0), max(0, int((stop - cursor).total_seconds() / 60))
                )
                take = min(remaining, free)
                if take:
                    used[key] = used.get(key, 0) + take
                    cursor += timedelta(minutes=take)
                    remaining -= take
                if remaining <= 0:
                    member_end[member_id] = cursor
                    return cursor
                cursor = datetime.combine(cursor.date() + timedelta(days=1), time(8), zone)
            return None

        for key in ordered:
            task = tasks[key]
            people = by_task[key]
            blocked = [p for p in predecessors[key] if not completed[p]]
            reasons = []
            finishes = []
            unknown = False
            if completed[key]:
                forecasts[key] = {
                    "task_id": key,
                    "title": task["title"],
                    "status": "complete",
                    "reasons": [],
                    "predecessor_ids": predecessors[key],
                    "blocked_by": [],
                    "forecast_finish": now.isoformat(),
                    "remaining_minutes": 0,
                    "assignee_ids": [a["user_id"] for a in people],
                }
                continue
            if blocked:
                reasons.append("Waiting for: " + ", ".join(tasks[p]["title"] for p in blocked))
            if not people:
                reasons.append("No one is assigned yet.")
                unknown = True
            known_predecessors = [forecasts[p]["forecast_finish"] for p in predecessors[key]]
            if any(p is None for p in known_predecessors):
                unknown = True
                reasons.append("A predecessor has no finish estimate yet.")
            after = max([now] + [datetime.fromisoformat(p) for p in known_predecessors if p])
            total = 0
            remaining_known = True
            for a in people:
                if a.get("outcome") == "success":
                    continue
                remaining = a.get("shared_remaining_minutes")
                if remaining is None:
                    remaining = task.get("estimated_duration_minutes")
                if remaining is None:
                    unknown_work[a["user_id"]] = True
                    remaining_known = False
                    unknown = True
                    reasons.append("Remaining work is missing for an assignee.")
                    continue
                total += remaining
                workload[a["user_id"]] += remaining
                if a.get("shared_progress") == "needs_help":
                    reasons.append("An assignee asked for help.")
                if unknown_work[a["user_id"]]:
                    unknown = True
                    reasons.append(
                        "This assignee has other work with an unknown remaining duration."
                    )
                if not unknown:
                    finish = allocate(a["user_id"], after, remaining)
                    if finish:
                        finishes.append(finish)
                    else:
                        unknown = True
                        reasons.append(
                            "An assignee has no sufficient, current shared availability."
                        )
            finish = max(finishes).isoformat() if finishes and not unknown else None
            deadline = None
            if task.get("due_date"):
                deadline = datetime.combine(
                    datetime.fromisoformat(task["due_date"]).date(),
                    time.fromisoformat(task.get("due_time") or "23:59:59"),
                    get_timezone(task.get("due_timezone_name") or timezone_name),
                )
            late = finish and deadline and datetime.fromisoformat(finish) > deadline
            if late:
                reasons.append("Estimated finish is after the task deadline.")
            forecasts[key] = {
                "task_id": key,
                "title": task["title"],
                "status": "at_risk"
                if late or any(a.get("shared_progress") == "needs_help" for a in people)
                else "unknown"
                if unknown
                else "blocked"
                if blocked
                else "scheduled",
                "reasons": sorted(set(reasons)),
                "predecessor_ids": predecessors[key],
                "blocked_by": blocked,
                "forecast_finish": finish,
                "remaining_minutes": total if remaining_known and people else None,
                "assignee_ids": [a["user_id"] for a in people],
            }
        milestones = []
        for milestone in self._rows("group_project_milestones", group_id):
            ids = [str(i) for i in milestone["task_ids"]]
            missing = [i for i in ids if i not in forecasts]
            items = [forecasts[i] for i in ids if i in forecasts]
            finishes = [item["forecast_finish"] for item in items if item["status"] != "complete"]
            finish = max(finishes) if finishes and all(finishes) else None
            deadline = datetime.combine(
                datetime.fromisoformat(milestone["due_date"]).date(),
                time(23, 59, 59),
                get_timezone(milestone.get("timezone_name") or "UTC"),
            )
            ready = (
                bool(items) and not missing and all(item["status"] == "complete" for item in items)
            )
            status = (
                "complete"
                if milestone.get("confirmed_at") and ready
                else "review"
                if ready
                else "unknown"
            )
            slack = None
            if not ready and finish and not missing:
                slack = int((deadline - datetime.fromisoformat(finish)).total_seconds() / 60)
                status = "at_risk" if slack < 0 else "on_track"
            milestones.append(
                {
                    **milestone,
                    "status": status,
                    "forecast_finish": finish,
                    "slack_minutes": slack,
                    "missing_task_ids": missing,
                }
            )
        loads = []
        for key, m in members.items():
            capacity = m.get("shared_minutes_per_day")
            until = m.get("capacity_until")
            days = (
                max(0, (datetime.fromisoformat(str(until)).date() - now.date()).days + 1)
                if until
                else 0
            )
            total_capacity = capacity * days if capacity is not None else None
            loads.append(
                {
                    "user_id": key,
                    "name": profiles.get(key, {}).get("display_name") or "Member",
                    "minutes_per_day": capacity,
                    "available_until": until,
                    "remaining_minutes": workload[key],
                    "has_unknown_work": unknown_work[key],
                    "capacity_minutes": total_capacity,
                    "spare_minutes": max(0, total_capacity - workload[key])
                    if total_capacity is not None
                    else None,
                }
            )
        suggestions = []
        for item in forecasts.values():
            if item["status"] in ("at_risk", "blocked"):
                helpers = [
                    m
                    for m in loads
                    if m["user_id"] not in item["assignee_ids"]
                    and m["spare_minutes"]
                    and not m["has_unknown_work"]
                ]
                suggestions.append(
                    {
                        "task_id": item["task_id"],
                        "title": item["title"],
                        "reason": (
                            "Discuss a smaller handoff or ask for help. "
                            "Assignment never changes automatically."
                        ),
                        "helper_ids": [
                            m["user_id"]
                            for m in sorted(helpers, key=lambda m: -m["spare_minutes"])[:3]
                        ],
                    }
                )
        for item in forecasts.values():
            descendants = set()
            frontier = [item["task_id"]]
            while frontier:
                current = frontier.pop()
                for edge in edges:
                    if edge["predecessor_id"] == current and edge["task_id"] not in descendants:
                        descendants.add(edge["task_id"])
                        frontier.append(edge["task_id"])
            item["downstream_count"] = sum(not completed.get(key, False) for key in descendants)
        requests = self._rows("group_help_requests", group_id)
        requests = [
            r
            for r in requests
            if r["requester_id"] in members
            and r["helper_id"] in members
            and any(a["user_id"] == r["requester_id"] for a in by_task.get(r["task_id"], []))
        ]
        return {
            "tasks": list(forecasts.values()),
            "dependencies": edges,
            "milestones": milestones,
            "workload": loads,
            "suggestions": suggestions,
            "help_requests": requests,
            "generated_at": now.isoformat(),
            "timezone_name": timezone_name,
            "assumptions": [
                "Rule-based schedule estimate, not a team success probability.",
                "Uses only explicitly shared availability and remaining work, never "
                "private schedules or scores.",
                "All calendar days are available within 08:00–22:00, up to each shared "
                "daily limit. Tasks are ordered by dependencies then due date.",
                "A shared estimate applies to each unfinished assignee unless they "
                "publish their own remaining time.",
                "Missing data stays unknown. Review and correction work must be added as tasks.",
            ],
        }

    def dependency(self, user_id, group_id, body, remove=False):
        self.groups._require_member(group_id, user_id)
        tasks = {r["id"] for r in self._rows("group_tasks", group_id)}
        if str(body.task_id) not in tasks or str(body.predecessor_id) not in tasks:
            raise ResourceNotFoundError("Both tasks must belong to this group.")
        if body.task_id == body.predecessor_id:
            raise DomainValidationError("A task cannot depend on itself.")
        if remove:
            self._execute(
                self.db.table("group_task_dependencies")
                .delete()
                .eq("group_id", str(group_id))
                .eq("task_id", str(body.task_id))
                .eq("predecessor_id", str(body.predecessor_id))
            )
            return {"removed": True}
        edges = self._rows("group_task_dependencies", group_id)
        visited = set()
        frontier = [str(body.predecessor_id)]
        while frontier:
            key = frontier.pop()
            if key == str(body.task_id):
                raise DomainValidationError("That dependency would create a cycle.")
            if key in visited:
                continue
            visited.add(key)
            frontier.extend(e["predecessor_id"] for e in edges if e["task_id"] == key)
        return self._execute(
            self.db.table("group_task_dependencies").insert(
                {
                    "group_id": str(group_id),
                    "task_id": str(body.task_id),
                    "predecessor_id": str(body.predecessor_id),
                }
            )
        ).data[0]

    def milestone(self, user_id, group_id, body):
        self.groups._require_member(group_id, user_id)
        ids = {t["id"] for t in self._rows("group_tasks", group_id)}
        if not body.task_ids or any(str(i) not in ids for i in body.task_ids):
            raise DomainValidationError("Choose tasks from this group for the milestone.")
        if not body.title.strip() or not body.completion_criteria.strip():
            raise DomainValidationError(
                "Add a milestone name and an observable completion criterion."
            )
        return self._execute(
            self.db.table("group_project_milestones").insert(
                {
                    "group_id": str(group_id),
                    **body.model_dump(mode="json"),
                    "title": body.title.strip(),
                    "completion_criteria": body.completion_criteria.strip(),
                }
            )
        ).data[0]

    def confirm_milestone(self, user_id, group_id, milestone_id):
        member = self.groups._require_member(group_id, user_id)
        if member["role"] not in ("owner", "admin"):
            raise PermissionDeniedError("An owner or admin must confirm milestone criteria.")
        state = self.forecast(user_id, group_id)
        milestone = next((m for m in state["milestones"] if m["id"] == str(milestone_id)), None)
        if not milestone:
            raise ResourceNotFoundError("Milestone not found.")
        if milestone["status"] not in ("review", "complete"):
            raise DomainValidationError(
                "Complete the linked tasks before confirming this milestone."
            )
        self._execute(
            self.db.table("group_project_milestones")
            .update({"confirmed_at": datetime.now(UTC).isoformat()})
            .eq("group_id", str(group_id))
            .eq("id", str(milestone_id))
        )
        return {"confirmed": True}

    def capacity(self, user_id, group_id, body):
        self.groups._require_member(group_id, user_id)
        if body.minutes_per_day is not None and (
            not body.available_until or body.available_until < datetime.now(UTC).date()
        ):
            raise DomainValidationError(
                "Choose an end date for the availability you want to share."
            )
        self._execute(
            self.db.table("group_members")
            .update(
                {
                    "shared_minutes_per_day": body.minutes_per_day,
                    "capacity_until": body.available_until.isoformat()
                    if body.minutes_per_day is not None and body.available_until
                    else None,
                }
            )
            .eq("group_id", str(group_id))
            .eq("user_id", str(user_id))
        )
        return {"saved": True}

    def remaining(self, user_id, group_id, task_id, body):
        self.groups.get_task_for_assignee(user_id, group_id, task_id)
        self._execute(
            self.db.table("group_task_assignees")
            .update(
                {
                    "shared_remaining_minutes": body.remaining_minutes,
                    "remaining_updated_at": datetime.now(UTC).isoformat(),
                }
            )
            .eq("group_id", str(group_id))
            .eq("task_id", str(task_id))
            .eq("user_id", str(user_id))
        )
        return {"saved": True}

    def help(self, user_id, group_id, body):
        self.groups.get_task_for_assignee(user_id, group_id, body.task_id)
        if body.helper_id == user_id or not self.groups.groups.get_membership(
            str(group_id), str(body.helper_id)
        ):
            raise DomainValidationError("Choose another current group member.")
        if not body.message.strip():
            raise DomainValidationError("Describe the small part you need help with.")
        return self._execute(
            self.db.table("group_help_requests").insert(
                {
                    "group_id": str(group_id),
                    "task_id": str(body.task_id),
                    "requester_id": str(user_id),
                    "helper_id": str(body.helper_id),
                    "message": body.message.strip(),
                }
            )
        ).data[0]

    def reply(self, user_id, group_id, request_id, body):
        self.groups._require_member(group_id, user_id)
        rows = self._execute(
            self.db.table("group_help_requests")
            .select("*")
            .eq("group_id", str(group_id))
            .eq("id", str(request_id))
            .eq("helper_id", str(user_id))
            .limit(1)
        ).data
        if not rows:
            raise ResourceNotFoundError("Help request not found.")
        request = rows[0]
        self.groups.get_task_for_assignee(
            UUID(request["requester_id"]), group_id, UUID(request["task_id"])
        )
        self._execute(
            self.db.table("group_help_requests")
            .update({"status": body.status})
            .eq("id", str(request_id))
            .eq("helper_id", str(user_id))
            .eq("status", "pending")
        )
        return {
            "saved": True,
            "note": "Agreement recorded. Discuss scope before changing task assignments.",
        }

    def project_timezone(self, user_id, group_id, body):
        membership = self.groups._require_member(group_id, user_id)
        if membership["role"] not in ("owner", "admin"):
            raise PermissionDeniedError("An owner or admin must change the project timezone.")
        self._execute(
            self.db.table("groups")
            .update({"planning_timezone_name": body.timezone_name})
            .eq("id", str(group_id))
        )
        return {"saved": True}

    def edit_milestone(self, user_id, group_id, milestone_id, body=None):
        self.groups._require_member(group_id, user_id)
        rows = self._execute(
            self.db.table("group_project_milestones")
            .select("*")
            .eq("group_id", str(group_id))
            .eq("id", str(milestone_id))
            .limit(1)
        ).data
        if not rows:
            raise ResourceNotFoundError("Milestone not found.")
        if body is None:
            self._execute(
                self.db.table("group_project_milestones")
                .delete()
                .eq("group_id", str(group_id))
                .eq("id", str(milestone_id))
            )
            return {"removed": True}
        ids = {r["id"] for r in self._rows("group_tasks", group_id)}
        if not body.task_ids or any(str(i) not in ids for i in body.task_ids):
            raise DomainValidationError("Choose tasks from this group.")
        if not body.title.strip() or not body.completion_criteria.strip():
            raise DomainValidationError("Add a milestone name and completion criterion.")
        changes = body.model_dump(mode="json")
        changes.update(
            title=body.title.strip(),
            completion_criteria=body.completion_criteria.strip(),
            confirmed_at=None,
        )
        return self._execute(
            self.db.table("group_project_milestones")
            .update(changes)
            .eq("group_id", str(group_id))
            .eq("id", str(milestone_id))
        ).data[0]
