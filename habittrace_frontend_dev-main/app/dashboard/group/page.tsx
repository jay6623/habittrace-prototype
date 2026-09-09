"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "@/app/providers";
import {
  ApiError,
  createGroup,
  createTask,
  getTasks,
  createGroupTask,
  deleteGroup,
  deleteGroupTask,
  getGroupDetail,
  getGroups,
  joinGroup,
  updateGroupTask,
  type Group,
  type GroupDetail,
  type GroupTask,
  type GroupTaskCreate,
  type GroupTaskStatus,
} from "@/lib/api";
import {
  describeApiError,
  formatDue,
  memberInitial,
  memberName,
  readStoredGroupId,
  storeGroupId,
} from "@/lib/group";
import QuickAddForm from "@/components/mobile/quick-add-form";
import Dialog from "@/components/ui/dialog";
import {
  localDateString,
  createQuickAddDefaults,
  toQuickTaskCreate,
  TASK_CATEGORIES,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import { useDataRefresh } from "@/lib/refresh";
import GroupSetup from "@/components/group/group-setup";
import GroupTaskForm from "@/components/group/group-task-form";

// ── Presentation maps ─────────────────────────────────────────────────────
type Tab = "tasks" | "members" | "overview";

interface ToastState {
  message: string;
  tone: "success" | "error";
}

const priorityBadge: Record<string, string> = {
  high: "bg-rose-100 text-rose-700",
  medium: "bg-amber-100 text-amber-700",
  low: "bg-slate-100 text-slate-600",
};

const categoryChip: Record<string, string> = {
  Work: "bg-violet-100 text-violet-800",
  Study: "bg-sky-100 text-sky-800",
  Chores: "bg-amber-100 text-amber-800",
  "Fitness/Health": "bg-emerald-100 text-emerald-800",
  "Errands/Admin": "bg-orange-100 text-orange-800",
  "Hobbies/Leisure": "bg-pink-100 text-pink-800",
  Social: "bg-indigo-100 text-indigo-800",
  Other: "bg-slate-100 text-slate-600",
};

const STATUS_OPTIONS: {
  value: GroupTaskStatus;
  label: string;
  active: string;
}[] = [
  { value: "pending", label: "Pending", active: "bg-slate-900 text-white" },
  { value: "success", label: "Done", active: "bg-emerald-600 text-white" },
  { value: "failed", label: "Not completed", active: "bg-rose-600 text-white" },
];

function rateTone(rate: number): { text: string; bar: string } {
  if (rate >= 70) return { text: "text-emerald-600", bar: "bg-emerald-400" };
  if (rate >= 50) return { text: "text-amber-500", bar: "bg-amber-400" };
  return { text: "text-rose-500", bar: "bg-rose-400" };
}

const secondaryButton =
  "px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm font-medium transition-colors disabled:opacity-60";
const primaryButton =
  "px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60";

// ── Component ─────────────────────────────────────────────────────────────
export default function GroupPage() {
  const { user } = useAuth();
  const userId = user?.id ?? null;

  const [groups, setGroups] = useState<Group[]>([]);
  const [groupsLoading, setGroupsLoading] = useState(true);
  const [groupsError, setGroupsError] = useState<string | null>(null);
  const [selectedGroupId, setSelectedGroupId] = useState<string | null>(null);
  const [detail, setDetail] = useState<GroupDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);

  const [assignment, setAssignment] = useState("all");
  const [copyDraft, setCopyDraft] = useState<QuickAddDraft | null>(null);
  const [confirmDelete, setConfirmDelete] = useState<
    GroupTask | "group" | null
  >(null);
  const [tab, setTab] = useState<Tab>("tasks");
  const [showInvite, setShowInvite] = useState(false);
  const [showSetup, setShowSetup] = useState(false);
  const [showAddTask, setShowAddTask] = useState(false);
  const [copied, setCopied] = useState(false);
  const [busyTaskId, setBusyTaskId] = useState<string | null>(null);
  const [deletingGroup, setDeletingGroup] = useState(false);
  const [toast, setToast] = useState<ToastState | null>(null);

  // ── Loading ─────────────────────────────────────────────────────────────
  const selectGroup = useCallback(
    (groupId: string | null) => {
      setSelectedGroupId(groupId);
      setShowInvite(false);
      if (userId) storeGroupId(userId, groupId);
    },
    [userId],
  );

  const loadGroups = useCallback(async () => {
    setGroupsLoading(true);
    setGroupsError(null);
    try {
      const list = await getGroups();
      setGroups(list);
      setSelectedGroupId((current) => {
        if (current && list.some((group) => group.id === current))
          return current;
        const stored = userId ? readStoredGroupId(userId) : null;
        if (stored && list.some((group) => group.id === stored)) return stored;
        return list[0]?.id ?? null;
      });
    } catch (caught) {
      setGroupsError(describeApiError(caught, "We couldn't load your groups."));
    } finally {
      setGroupsLoading(false);
    }
  }, [userId]);

  const loadDetail = useCallback(
    async (groupId: string) => {
      setDetailLoading(true);
      setDetailError(null);
      try {
        setDetail(await getGroupDetail(groupId));
      } catch (caught) {
        if (caught instanceof ApiError && caught.status === 404) {
          // Deleted, or the user was removed, since the list loaded.
          setToast({
            message: "That group is no longer available.",
            tone: "error",
          });
          selectGroup(null);
          void loadGroups();
          return;
        }
        setDetailError(
          describeApiError(caught, "We couldn't load this group."),
        );
      } finally {
        setDetailLoading(false);
      }
    },
    [loadGroups, selectGroup],
  );

  useEffect(() => {
    void loadGroups();
  }, [loadGroups]);

  useEffect(() => {
    if (selectedGroupId) void loadDetail(selectedGroupId);
  }, [selectedGroupId, loadDetail]);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 3_500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 2_000);
    return () => window.clearTimeout(timer);
  }, [copied]);

  const refresh = useCallback(() => {
    void loadGroups();
    if (selectedGroupId) void loadDetail(selectedGroupId);
  }, [loadGroups, loadDetail, selectedGroupId]);
  useDataRefresh(refresh);

  // ── Derived state ───────────────────────────────────────────────────────
  const selectedGroup =
    groups.find((group) => group.id === selectedGroupId) ?? null;
  const activeDetail =
    detail && detail.group.id === selectedGroupId ? detail : null;
  const tasks = useMemo(() => activeDetail?.tasks ?? [], [activeDetail]);
  const members = useMemo(() => activeDetail?.members ?? [], [activeDetail]);

  const visibleTasks = tasks.filter(
    (task) =>
      assignment === "all" ||
      (assignment === "mine" ? task.assigned_to === userId : !task.assigned_to),
  );
  const done = tasks.filter((task) => task.status === "success").length;
  const failed = tasks.filter((task) => task.status === "failed").length;
  const pending = tasks.length - done - failed;
  const groupRate = tasks.length ? Math.round((done / tasks.length) * 100) : 0;
  const assignedToMe = tasks.filter(
    (task) => task.assigned_to === userId && task.status === "pending",
  ).length;

  const memberStats = useMemo(() => {
    const stats = new Map<string, { assigned: number; done: number }>();
    for (const member of members)
      stats.set(member.user_id, { assigned: 0, done: 0 });
    for (const task of tasks) {
      if (!task.assigned_to) continue;
      const entry = stats.get(task.assigned_to);
      if (!entry) continue;
      entry.assigned += 1;
      if (task.status === "success") entry.done += 1;
    }
    return stats;
  }, [members, tasks]);

  // ── Handlers ────────────────────────────────────────────────────────────
  async function handleCreateGroup(name: string) {
    const created = await createGroup(name);
    setGroups((current) => [...current, created]);
    selectGroup(created.id);
    setShowSetup(false);
    setShowInvite(true);
    setToast({
      message: "Group created. Share the invite code with your team.",
      tone: "success",
    });
  }

  async function handleJoinGroup(inviteCode: string) {
    const joined = await joinGroup(inviteCode);
    setGroups((current) =>
      current.some((group) => group.id === joined.id)
        ? current
        : [...current, joined],
    );
    selectGroup(joined.id);
    setShowSetup(false);
    setToast({ message: `You joined ${joined.name}.`, tone: "success" });
  }

  async function handleCreateTask(input: GroupTaskCreate) {
    if (!selectedGroupId) return;
    const created = await createGroupTask(selectedGroupId, input);
    setDetail((current) =>
      current && current.group.id === selectedGroupId
        ? { ...current, tasks: [created, ...current.tasks] }
        : current,
    );
    setShowAddTask(false);
    setToast({ message: "Task added for the group.", tone: "success" });
  }

  function replaceTask(next: GroupTask) {
    setDetail((current) =>
      current && current.group.id === next.group_id
        ? {
            ...current,
            tasks: current.tasks.map((task) =>
              task.id === next.id ? next : task,
            ),
          }
        : current,
    );
  }

  async function handleStatusChange(task: GroupTask, status: GroupTaskStatus) {
    if (task.status === status || busyTaskId) return;
    setBusyTaskId(task.id);
    replaceTask({ ...task, status });
    try {
      replaceTask(await updateGroupTask(task.group_id, task.id, { status }));
    } catch (caught) {
      replaceTask(task);
      setToast({
        message: describeApiError(caught, "We couldn't update that task."),
        tone: "error",
      });
    } finally {
      setBusyTaskId(null);
    }
  }

  async function handleDeleteTask(task: GroupTask) {
    if (busyTaskId) return;

    setBusyTaskId(task.id);
    try {
      await deleteGroupTask(task.group_id, task.id);
      setDetail((current) =>
        current && current.group.id === task.group_id
          ? {
              ...current,
              tasks: current.tasks.filter((item) => item.id !== task.id),
            }
          : current,
      );
    } catch (caught) {
      setToast({
        message: describeApiError(caught, "We couldn't delete that task."),
        tone: "error",
      });
    } finally {
      setBusyTaskId(null);
    }
  }

  async function handleDeleteGroup() {
    if (!selectedGroup || deletingGroup) return;
    setDeletingGroup(true);
    try {
      await deleteGroup(selectedGroup.id);
      const remaining = groups.filter((group) => group.id !== selectedGroup.id);
      setGroups(remaining);
      setDetail(null);
      selectGroup(remaining[0]?.id ?? null);
      setToast({
        message: `${selectedGroup.name} was deleted.`,
        tone: "success",
      });
    } catch (caught) {
      setToast({
        message: describeApiError(caught, "We couldn't delete this group."),
        tone: "error",
      });
    } finally {
      setDeletingGroup(false);
    }
  }

  function handleCopyInvite() {
    if (!selectedGroup) return;
    const clipboard =
      typeof navigator !== "undefined" ? navigator.clipboard : undefined;
    if (!clipboard) {
      setToast({
        message: "Copying isn't available here. Select the code to copy it.",
        tone: "error",
      });
      return;
    }
    clipboard
      .writeText(selectedGroup.invite_code)
      .then(() => setCopied(true))
      .catch(() =>
        setToast({
          message: "Copying failed. Select the code to copy it.",
          tone: "error",
        }),
      );
  }

  const closeAddTask = useCallback(() => setShowAddTask(false), []);

  // ── Render ──────────────────────────────────────────────────────────────
  const header = (
    <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <div className="flex items-center gap-2">
          <div className="text-sm text-slate-500">Group Scheduling</div>
          <span className="text-xs px-2 py-0.5 rounded-full bg-violet-100 text-violet-700 font-medium">
            Beta
          </span>
        </div>
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-bold">
            {selectedGroup?.name ?? "Your groups"}
          </h1>
          {groups.length > 1 && (
            <select
              aria-label="Switch group"
              className="text-sm rounded-xl border border-slate-200 bg-white px-3 py-1.5 text-slate-700"
              onChange={(event) => selectGroup(event.target.value)}
              value={selectedGroupId ?? ""}
            >
              {groups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </select>
          )}
        </div>
      </div>
      {groups.length > 0 && (
        <div className="flex gap-2 flex-wrap">
          <button
            className={secondaryButton}
            onClick={() => setShowSetup((open) => !open)}
            type="button"
          >
            New / Join
          </button>
          <button
            className={secondaryButton}
            disabled={!selectedGroup}
            onClick={() => setShowInvite((open) => !open)}
            type="button"
          >
            Invite member
          </button>
          <button
            className={primaryButton}
            disabled={!activeDetail}
            onClick={() => setShowAddTask(true)}
            type="button"
          >
            + Add group task
          </button>
        </div>
      )}
    </div>
  );

  if (groupsLoading) {
    return (
      <div className="space-y-5">
        {header}
        <div className="bg-white rounded-2xl border border-slate-200 p-8 text-center text-sm text-slate-400 animate-pulse">
          Loading your groups…
        </div>
      </div>
    );
  }

  if (groupsError) {
    return (
      <div className="space-y-5">
        {header}
        <div className="px-4 py-3 rounded-xl bg-amber-50 border border-amber-100 text-sm text-amber-700 flex items-center justify-between gap-3">
          <span>{groupsError}</span>
          <button
            className={secondaryButton}
            onClick={() => void loadGroups()}
            type="button"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (groups.length === 0) {
    return (
      <div className="space-y-5">
        {header}
        <GroupSetup
          mode="empty"
          onCreate={handleCreateGroup}
          onJoin={handleJoinGroup}
        />
        <div className="text-xs text-slate-400 text-center py-2">
          Group scheduling is in Beta — teammates see changes when they refresh.
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      {header}

      {showSetup && (
        <GroupSetup
          mode="panel"
          onCreate={handleCreateGroup}
          onDismiss={() => setShowSetup(false)}
          onJoin={handleJoinGroup}
        />
      )}

      {/* Invite panel */}
      {showInvite && selectedGroup && (
        <div className="bg-white rounded-2xl border border-violet-200 p-5">
          <div className="font-semibold mb-1">
            Invite to {selectedGroup.name}
          </div>
          <div className="text-sm text-slate-500 mb-3">
            Share this code with teammates — they can join from their HabitTrace
            account using &quot;New / Join&quot;.
          </div>
          <div className="flex gap-2">
            <div className="flex-1 bg-slate-100 rounded-xl px-4 py-3 font-mono text-sm tracking-wider text-slate-700 select-all">
              {selectedGroup.invite_code}
            </div>
            <button
              className={`${primaryButton} py-3`}
              onClick={handleCopyInvite}
              type="button"
            >
              {copied ? "Copied ✓" : "Copy"}
            </button>
          </div>
        </div>
      )}

      {detailError && (
        <div className="px-4 py-3 rounded-xl bg-amber-50 border border-amber-100 text-sm text-amber-700 flex items-center justify-between gap-3">
          <span>{detailError}</span>
          <button
            className={secondaryButton}
            onClick={() => selectedGroupId && void loadDetail(selectedGroupId)}
            type="button"
          >
            Retry
          </button>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Group success rate</div>
          <div
            className={`text-2xl font-bold mt-1 ${tasks.length ? "text-emerald-600" : "text-slate-400"}`}
          >
            {tasks.length ? `${groupRate}%` : "—"}
          </div>
          <div className="mt-2 h-2 rounded-full bg-slate-100 overflow-hidden">
            <div
              className="h-full bg-emerald-400 rounded-full"
              style={{ width: `${groupRate}%` }}
            />
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Group tasks</div>
          <div className="flex items-baseline gap-1 mt-1">
            <span className="text-2xl font-bold text-emerald-600">{done}</span>
            <span className="text-sm text-slate-500">/ {tasks.length}</span>
          </div>
          <div className="text-xs text-slate-500 mt-1">
            {pending} pending{failed ? ` · ${failed} failed` : ""}
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Members</div>
          <div className="text-2xl font-bold mt-1">{members.length || "—"}</div>
          <div className="text-xs text-slate-500 mt-1 capitalize">
            {selectedGroup ? `You are the ${selectedGroup.role}` : ""}
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Assigned to you</div>
          <div className="text-2xl font-bold mt-1">{assignedToMe}</div>
          <div className="text-xs text-slate-500 mt-1">pending</div>
        </div>
      </div>

      {/* Tab navigation */}
      <div className="flex rounded-xl border border-slate-200 overflow-hidden w-fit">
        {(["tasks", "members", "overview"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            type="button"
            className={`px-4 py-2 text-sm font-medium capitalize transition-colors border-r border-slate-200 last:border-r-0 ${
              tab === t
                ? "bg-slate-900 text-white"
                : "bg-white text-slate-500 hover:text-slate-700"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {detailLoading && !activeDetail && (
        <div className="bg-white rounded-2xl border border-slate-200 p-8 text-center text-sm text-slate-400 animate-pulse">
          Loading {selectedGroup?.name ?? "group"}…
        </div>
      )}

      {/* Tasks tab */}
      {activeDetail && tab === "tasks" && (
        <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
          <div className="p-5 border-b border-slate-200">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="font-semibold">Group tasks</div>
              <select
                aria-label="Filter by assignment"
                className="field !w-auto"
                value={assignment}
                onChange={(e) => setAssignment(e.target.value)}
              >
                <option value="all">Everyone’s tasks</option>
                <option value="mine">Assigned to me</option>
                <option value="unassigned">Unassigned</option>
              </select>
            </div>
            <div className="text-sm text-slate-500">
              Shared tasks assigned to team members
            </div>
          </div>
          {visibleTasks.length === 0 ? (
            <div className="p-8 text-center">
              <div className="text-sm text-slate-500 mb-3">
                No shared tasks match this view.
              </div>
              <button
                className={primaryButton}
                onClick={() => setShowAddTask(true)}
                type="button"
              >
                + Add the first task
              </button>
            </div>
          ) : (
            <div className="divide-y divide-slate-100">
              {visibleTasks.map((task) => {
                const busy = busyTaskId === task.id;
                const due = formatDue(task);
                const assignee = task.assigned_to
                  ? memberName(
                      {
                        user_id: task.assigned_to,
                        display_name: task.assignee_name,
                      },
                      userId,
                    )
                  : "Unassigned";
                return (
                  <div
                    key={task.id}
                    className={`px-5 py-4 ${
                      task.status === "success"
                        ? "bg-emerald-50/40"
                        : task.status === "failed"
                          ? "bg-rose-50/40"
                          : ""
                    }`}
                  >
                    <div className="flex flex-wrap items-start gap-3">
                      <div
                        className={`mt-1.5 h-3 w-3 rounded-full shrink-0 ${
                          task.status === "success"
                            ? "bg-emerald-400"
                            : task.status === "failed"
                              ? "bg-rose-400"
                              : "bg-slate-300"
                        }`}
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span
                            className={`text-sm font-medium ${task.status !== "pending" ? "text-slate-400 line-through" : ""}`}
                          >
                            {task.title}
                          </span>
                          <span
                            className={`text-xs px-2 py-0.5 rounded-full ${categoryChip[task.category] ?? "bg-slate-100 text-slate-600"}`}
                          >
                            {task.category}
                          </span>
                          <span
                            className={`text-xs px-2 py-0.5 rounded-full ${priorityBadge[task.priority]}`}
                          >
                            {task.priority}
                          </span>
                        </div>
                        <div className="text-xs text-slate-500 mt-1">
                          Assigned to{" "}
                          <span className="font-medium">{assignee}</span>
                          {due && <> · Due {due}</>}
                        </div>
                      </div>
                      <div className="flex flex-wrap items-center gap-2">
                        <button
                          className="btn-secondary"
                          onClick={() =>
                            setCopyDraft({
                              title: task.title,
                              plannedDate: task.due_date ?? localDateString(),
                              plannedTime:
                                task.due_time?.slice(0, 5) ??
                                createQuickAddDefaults().plannedTime,
                              durationMinutes: 30,
                              category: TASK_CATEGORIES.includes(
                                task.category as QuickAddDraft["category"],
                              )
                                ? (task.category as QuickAddDraft["category"])
                                : "Other",
                              importance:
                                task.priority === "high"
                                  ? 5
                                  : task.priority === "low"
                                    ? 2
                                    : 3,
                            })
                          }
                        >
                          Copy to my plans
                        </button>
                        <div
                          aria-label={`Status for ${task.title}`}
                          className="flex rounded-lg border border-slate-200 overflow-hidden"
                          role="group"
                        >
                          {STATUS_OPTIONS.map((option) => (
                            <button
                              aria-pressed={task.status === option.value}
                              className={`px-2.5 py-1 text-xs font-medium transition-colors border-r border-slate-200 last:border-r-0 disabled:opacity-60 ${
                                task.status === option.value
                                  ? option.active
                                  : "bg-white text-slate-500 hover:bg-slate-50"
                              }`}
                              disabled={busy}
                              key={option.value}
                              onClick={() =>
                                void handleStatusChange(task, option.value)
                              }
                              type="button"
                            >
                              {option.label}
                            </button>
                          ))}
                        </div>
                        <button
                          aria-label={`Delete ${task.title}`}
                          className="h-7 w-7 grid place-items-center rounded-lg text-slate-400 hover:bg-rose-50 hover:text-rose-600 transition-colors disabled:opacity-60"
                          disabled={busy}
                          onClick={() => setConfirmDelete(task)}
                          type="button"
                        >
                          ×
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Members tab */}
      {activeDetail && tab === "members" && (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          {members.map((member) => {
            const name = memberName(member, userId);
            const stats = memberStats.get(member.user_id) ?? {
              assigned: 0,
              done: 0,
            };
            const rate = stats.assigned
              ? Math.round((stats.done / stats.assigned) * 100)
              : null;
            const tone = rate === null ? null : rateTone(rate);
            return (
              <div
                key={member.user_id}
                className="bg-white rounded-2xl border border-slate-200 p-5"
              >
                <div className="flex items-center gap-3 mb-3">
                  <div className="h-11 w-11 rounded-full bg-slate-900 text-white grid place-items-center font-bold text-sm">
                    {memberInitial(name)}
                  </div>
                  <div className="min-w-0">
                    <div className="font-semibold text-sm truncate">{name}</div>
                    <div className="text-xs text-slate-500 capitalize">
                      {member.role}
                    </div>
                  </div>
                </div>
                <div className="space-y-2">
                  <div className="flex justify-between text-xs">
                    <span className="text-slate-500">Assigned tasks</span>
                    <span className="font-medium">{stats.assigned}</span>
                  </div>
                  <div className="flex justify-between text-xs">
                    <span className="text-slate-500">Completed</span>
                    <span
                      className={`font-medium ${tone?.text ?? "text-slate-400"}`}
                    >
                      {rate === null
                        ? "No tasks yet"
                        : `${stats.done} · ${rate}%`}
                    </span>
                  </div>
                  <div className="h-1.5 rounded-full bg-slate-100 overflow-hidden mt-1">
                    <div
                      className={`h-full rounded-full ${tone?.bar ?? "bg-slate-200"}`}
                      style={{ width: `${rate ?? 0}%` }}
                    />
                  </div>
                </div>
              </div>
            );
          })}
          {members.length === 1 && (
            <div className="rounded-2xl border border-dashed border-slate-300 p-5 flex flex-col items-start justify-center gap-2">
              <div className="text-sm font-medium">
                It&apos;s just you so far
              </div>
              <div className="text-xs text-slate-500">
                Share the invite code so teammates can join.
              </div>
              <button
                className={secondaryButton}
                onClick={() => setShowInvite(true)}
                type="button"
              >
                Show invite code
              </button>
            </div>
          )}
        </div>
      )}

      {/* Overview tab */}
      {activeDetail && tab === "overview" && (
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-5">
          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-4">Task completion by member</div>
            <div className="space-y-4">
              {members.map((member) => {
                const stats = memberStats.get(member.user_id) ?? {
                  assigned: 0,
                  done: 0,
                };
                const rate = stats.assigned
                  ? Math.round((stats.done / stats.assigned) * 100)
                  : 0;
                return (
                  <div key={member.user_id}>
                    <div className="flex justify-between text-sm mb-1">
                      <span>{memberName(member, userId)}</span>
                      <span className="text-slate-500">
                        {stats.assigned
                          ? `${stats.done} / ${stats.assigned}`
                          : "No tasks"}
                      </span>
                    </div>
                    <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div
                        className={`h-full rounded-full ${stats.assigned ? rateTone(rate).bar : "bg-slate-200"}`}
                        style={{ width: `${rate}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="space-y-5">
            <div className="bg-white rounded-2xl border border-slate-200 p-5">
              <div className="font-semibold mb-4">Recently added</div>
              {visibleTasks.length === 0 ? (
                <div className="text-sm text-slate-500">
                  Nothing yet — add a group task to get started.
                </div>
              ) : (
                <div className="space-y-3">
                  {tasks.slice(0, 5).map((task) => (
                    <div
                      key={task.id}
                      className="flex flex-wrap items-start gap-3"
                    >
                      <div
                        className={`mt-1.5 h-2 w-2 rounded-full shrink-0 ${
                          task.status === "success"
                            ? "bg-emerald-400"
                            : task.status === "failed"
                              ? "bg-rose-400"
                              : "bg-sky-400"
                        }`}
                      />
                      <div className="text-sm min-w-0">
                        <span className="text-slate-700">
                          &quot;{task.title}&quot;
                        </span>
                        <span className="text-xs text-slate-400 ml-2">
                          {task.assigned_to
                            ? memberName(
                                {
                                  user_id: task.assigned_to,
                                  display_name: task.assignee_name,
                                },
                                userId,
                              )
                            : "Unassigned"}
                          {" · "}
                          {task.status === "success"
                            ? "Done"
                            : task.status === "failed"
                              ? "Failed"
                              : "Pending"}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {selectedGroup?.role === "owner" && (
              <div className="bg-white rounded-2xl border border-rose-100 p-5">
                <div className="font-semibold mb-1">Delete group</div>
                <div className="text-sm text-slate-500 mb-3">
                  Removes the group and all of its shared tasks for every
                  member.
                </div>
                <button
                  className="px-4 py-2 rounded-xl border border-rose-200 text-rose-700 hover:bg-rose-50 text-sm font-medium transition-colors disabled:opacity-60"
                  disabled={deletingGroup}
                  onClick={() => setConfirmDelete("group")}
                  type="button"
                >
                  {deletingGroup ? "Deleting…" : "Delete this group"}
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      <div className="text-xs text-slate-400 text-center py-2">
        Group scheduling is in Beta — teammates see changes when they refresh.
      </div>

      {toast && (
        <div
          aria-live="polite"
          className={`fixed left-1/2 top-4 z-[60] w-[calc(100%-2rem)] max-w-md -translate-x-1/2 rounded-2xl px-4 py-3 text-center text-sm font-bold shadow-xl ${
            toast.tone === "success"
              ? "bg-emerald-600 text-white"
              : "bg-rose-600 text-white"
          }`}
          role={toast.tone === "error" ? "alert" : "status"}
        >
          {toast.message}
        </div>
      )}

      {copyDraft && (
        <QuickAddForm
          initialDraft={copyDraft}
          onDismiss={() => setCopyDraft(null)}
          onSubmit={async (draft) => {
            const existing = await getTasks(draft.plannedDate);
            await createTask(toQuickTaskCreate(draft, existing.length + 1));
            setCopyDraft(null);
            setToast({
              tone: "success",
              message:
                "Personal copy created. Changes to this copy do not update the group task.",
            });
          }}
        />
      )}
      {confirmDelete && (
        <Dialog
          title="Delete for everyone?"
          busy={!!busyTaskId || deletingGroup}
          onClose={() => setConfirmDelete(null)}
        >
          <p className="mb-5 text-sm">
            {confirmDelete === "group"
              ? "This group and its shared tasks"
              : `“${confirmDelete.title}”`}{" "}
            will be permanently removed for every member.
          </p>
          <div className="flex gap-3">
            <button
              className="btn-secondary"
              disabled={!!busyTaskId || deletingGroup}
              onClick={() => setConfirmDelete(null)}
            >
              Cancel
            </button>
            <button
              className="btn-primary !bg-rose-700"
              disabled={!!busyTaskId || deletingGroup}
              onClick={async () => {
                if (confirmDelete === "group") await handleDeleteGroup();
                else await handleDeleteTask(confirmDelete);
                setConfirmDelete(null);
              }}
            >
              Delete
            </button>
          </div>
        </Dialog>
      )}
      {showAddTask && activeDetail && (
        <GroupTaskForm
          currentUserId={userId}
          members={activeDetail.members}
          onDismiss={closeAddTask}
          onSubmit={handleCreateTask}
        />
      )}
    </div>
  );
}
