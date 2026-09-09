"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useDataRefresh } from "@/lib/refresh";
import { useToast } from "@/components/ui/toast";
import { useAuth } from "@/app/providers";
import {
  completeExecution,
  createMobileAIOutcome,
  createTask,
  getActiveExecutions,
  getTask,
  getTasks,
  startExecution,
  type Execution,
  type Task,
} from "@/lib/api";
import {
  formatTaskTime,
  localDateString,
  taskTimeInMinutes,
  toQuickTaskCreate,
  type FailureReasonCode,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import OutcomeSheet, {
  type MobileResult,
  type OutcomeTimes,
} from "./outcome-sheet";
import QuickAddForm from "./quick-add-form";

interface ToastState {
  message: string;
  tone: "success" | "error";
}

function taskSort(left: Task, right: Task): number {
  return (
    taskTimeInMinutes(left.planned_start_time) -
    taskTimeInMinutes(right.planned_start_time)
  );
}

function readableError(caught: unknown, fallback: string): string {
  if (!(caught instanceof Error)) return fallback;
  if (
    caught.message.includes("Failed to fetch") ||
    caught.message.includes("fetch")
  ) {
    return "We couldn't connect. Check your network and try again.";
  }
  const message = caught.message.toLowerCase();
  if (
    caught.message.includes("401") ||
    message.includes("sign in") ||
    message.includes("session")
  ) {
    return "Your session has expired. Please sign in again.";
  }
  return fallback;
}

function formatStartedAt(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
  });
}

export default function MobileToday() {
  const { displayName } = useAuth();
  const notifications = useToast();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [activeExecutions, setActiveExecutions] = useState<
    Record<string, Execution>
  >({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [online, setOnline] = useState(true);
  const [nowMinutes, setNowMinutes] = useState(() => {
    const now = new Date();
    return now.getHours() * 60 + now.getMinutes();
  });
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [startingTaskId, setStartingTaskId] = useState<string | null>(null);
  const [outcomeSaving, setOutcomeSaving] = useState(false);
  const [outcomeError, setOutcomeError] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastState | null>(null);

  const today = localDateString();

  const loadToday = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    try {
      const [todayTasks, active] = await Promise.all([
        getTasks(today),
        getActiveExecutions(),
      ]);
      const knownTaskIds = new Set(todayTasks.map((task) => task.id));
      const missingTaskIds = Array.from(
        new Set(active.map((execution) => execution.task_id)),
      ).filter((taskId) => !knownTaskIds.has(taskId));
      const missingResults = await Promise.allSettled(
        missingTaskIds.map(getTask),
      );
      const activeTasks = missingResults.flatMap((result) =>
        result.status === "fulfilled" ? [result.value] : [],
      );

      setTasks([...todayTasks, ...activeTasks].sort(taskSort));
      setActiveExecutions(
        active.reduce<Record<string, Execution>>((byTask, execution) => {
          if (!byTask[execution.task_id]) byTask[execution.task_id] = execution;
          return byTask;
        }, {}),
      );
    } catch (caught) {
      setLoadError(readableError(caught, "We couldn't load today's plans."));
    } finally {
      setLoading(false);
    }
  }, [today]);

  useDataRefresh(loadToday);

  useEffect(() => {
    void loadToday();
  }, [loadToday]);

  useEffect(() => {
    setOnline(navigator.onLine);
    const handleOnline = () => {
      setOnline(true);
      void loadToday();
    };
    const handleOffline = () => setOnline(false);
    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);
    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, [loadToday]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      const now = new Date();
      setNowMinutes(now.getHours() * 60 + now.getMinutes());
    }, 60_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    function syncQuickAddHash() {
      if (window.location.hash === "#quick-add") setQuickAddOpen(true);
    }
    syncQuickAddHash();
    window.addEventListener("hashchange", syncQuickAddHash);
    return () => window.removeEventListener("hashchange", syncQuickAddHash);
  }, []);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 3_500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const todayPending = useMemo(
    () =>
      tasks.filter(
        (task) => task.planned_date === today && task.task_status === "pending",
      ),
    [tasks, today],
  );

  const currentTask = useMemo(() => {
    const activeTask = tasks
      .filter(
        (task) => task.task_status === "pending" && activeExecutions[task.id],
      )
      .sort((left, right) => {
        const leftStarted = Date.parse(activeExecutions[left.id].created_at);
        const rightStarted = Date.parse(activeExecutions[right.id].created_at);
        return rightStarted - leftStarted;
      })[0];
    if (activeTask) return activeTask;

    return (
      [...todayPending].sort((left, right) => {
        const leftDistance = Math.abs(
          taskTimeInMinutes(left.planned_start_time) - nowMinutes,
        );
        const rightDistance = Math.abs(
          taskTimeInMinutes(right.planned_start_time) - nowMinutes,
        );
        return leftDistance - rightDistance;
      })[0] ?? null
    );
  }, [activeExecutions, nowMinutes, tasks, todayPending]);

  const remainingTasks = todayPending
    .filter((task) => task.id !== currentTask?.id)
    .sort(taskSort);

  function closeQuickAdd() {
    setQuickAddOpen(false);
    if (window.location.hash === "#quick-add") {
      window.history.replaceState(
        null,
        "",
        `${window.location.pathname}${window.location.search}`,
      );
    }
  }

  async function handleQuickAdd(draft: QuickAddDraft) {
    const plansForDate =
      draft.plannedDate === today
        ? tasks.filter((task) => task.planned_date === today)
        : await getTasks(draft.plannedDate);
    const created = await createTask(
      toQuickTaskCreate(draft, plansForDate.length + 1),
    );
    setTasks((current) => {
      if (current.some((task) => task.id === created.id)) return current;
      return [...current, created].sort(taskSort);
    });
    closeQuickAdd();
    setToast({
      message:
        draft.plannedDate === today
          ? "Plan added to today's list."
          : `Plan saved for ${draft.plannedDate}.`,
      tone: "success",
    });
  }

  async function ensureStarted(task: Task): Promise<Execution> {
    const existing = activeExecutions[task.id];
    if (existing) return existing;
    const started = await startExecution(task.id);
    setActiveExecutions((current) => ({ ...current, [task.id]: started }));
    return started;
  }

  async function handleStart(task: Task) {
    if (startingTaskId || activeExecutions[task.id]) return;
    setStartingTaskId(task.id);
    try {
      const started = await ensureStarted(task);
      setToast({
        message: `Started at ${formatStartedAt(started.actual_start_time)}.`,
        tone: "success",
      });
    } catch (caught) {
      setToast({
        message: readableError(caught, "We couldn't record the start time."),
        tone: "error",
      });
    } finally {
      setStartingTaskId(null);
    }
  }

  function openOutcome(task: Task) {
    setOutcomeError(null);
    setSelectedTask(task);
  }

  async function handleOutcome(
    result: MobileResult,
    reason?: FailureReasonCode,
    times?: OutcomeTimes,
  ) {
    if (!selectedTask || outcomeSaving) return;
    setOutcomeSaving(true);
    setOutcomeError(null);
    try {
      const started = await ensureStarted(selectedTask);
      if (result === "in_progress") {
        setSelectedTask(null);
        setToast({ message: "Plan kept in progress.", tone: "success" });
        return;
      }

      const legacyStatus = result === "completed" ? "success" : "failed";
      const completed = await completeExecution(started.id, {
        ...times,
        task_status: legacyStatus,
        stopped_early: result !== "completed",
        interruption_count: 0,
        failure_reason: reason,
      });

      const completedTask = selectedTask;
      setTasks((current) =>
        current.map((task) =>
          task.id === completedTask.id
            ? { ...task, task_status: legacyStatus }
            : task,
        ),
      );
      setActiveExecutions((current) => {
        const next = { ...current };
        delete next[completedTask.id];
        return next;
      });
      setSelectedTask(null);
      setToast({ message: "Outcome saved.", tone: "success" });

      void createMobileAIOutcome({
        task: completedTask,
        execution: completed,
        outcomeStatus: result,
        failureReason: reason,
      }).catch((caught) => {
        console.warn("AI V2 outcome was not created:", caught);
        notifications.warn(
          "Outcome saved",
          "AI learning could not update this time. Your plan record is safe.",
        );
      });
    } catch (caught) {
      setOutcomeError(
        readableError(caught, "We couldn't save the outcome. Try again."),
      );
    } finally {
      setOutcomeSaving(false);
    }
  }

  const formattedDate = new Date(`${today}T12:00:00`).toLocaleDateString(
    "en-US",
    {
      month: "long",
      day: "numeric",
      weekday: "long",
    },
  );

  return (
    <section className="mx-auto w-full max-w-4xl text-slate-950" lang="en">
      <header className="flex items-start justify-between gap-4 py-3">
        <div>
          <p className="text-sm font-medium text-slate-500">{formattedDate}</p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight">
            {displayName ? `Today, ${displayName}` : "Today"}
          </h1>
        </div>
        <Link
          aria-label="Open account settings"
          className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-slate-950 text-sm font-bold text-white shadow-sm transition hover:bg-slate-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-950"
          href="/dashboard/settings"
        >
          HT
        </Link>
      </header>

      {!online && (
        <div
          className="mt-2 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm font-medium text-amber-900"
          role="status"
        >
          You&apos;re offline. Reconnect before saving or changing a plan.
        </div>
      )}

      {loading && tasks.length === 0 ? (
        <div
          aria-label="Loading today's plans"
          className="mt-5 space-y-3"
          role="status"
        >
          <div className="h-56 animate-pulse rounded-3xl bg-slate-200" />
          <div className="h-20 animate-pulse rounded-2xl bg-slate-200" />
        </div>
      ) : loadError && tasks.length === 0 ? (
        <section className="mt-5 rounded-3xl border border-rose-200 bg-white p-6 text-center">
          <h2 className="text-lg font-bold">Couldn&apos;t load your plans</h2>
          <p className="mt-2 text-sm leading-relaxed text-slate-600">
            {loadError}
          </p>
          <button
            className="mt-5 min-h-12 w-full rounded-2xl bg-slate-950 px-4 font-bold text-white disabled:opacity-50"
            disabled={!online || loading}
            onClick={() => void loadToday()}
            type="button"
          >
            Try again
          </button>
        </section>
      ) : (
        <>
          <div
            className="mt-5 grid grid-cols-3 gap-3"
            aria-label="Today’s progress"
          >
            {[
              {
                label: "Completed",
                value: tasks.filter(
                  (t) =>
                    t.planned_date === today && t.task_status === "success",
                ).length,
              },
              { label: "Remaining", value: todayPending.length },
              {
                label: "Planned minutes",
                value: todayPending.reduce(
                  (n, t) => n + t.planned_duration_min,
                  0,
                ),
              },
            ].map((item) => (
              <div
                key={item.label}
                className="rounded-2xl border border-slate-200 bg-white p-4"
              >
                <p className="text-2xl font-bold">{item.value}</p>
                <p className="mt-1 text-xs text-slate-500">{item.label}</p>
              </div>
            ))}
          </div>
          <section className="mt-5" aria-labelledby="current-plan-title">
            <div className="mb-3 flex items-center justify-between">
              <h2
                className="text-sm font-bold text-slate-700"
                id="current-plan-title"
              >
                {currentTask && activeExecutions[currentTask.id]
                  ? "IN PROGRESS"
                  : "UP NEXT"}
              </h2>
              <span className="text-xs font-medium text-slate-400">
                {todayPending.length} left
              </span>
            </div>

            {currentTask ? (
              <div className="rounded-3xl bg-slate-950 p-5 text-white shadow-xl shadow-slate-300">
                {activeExecutions[currentTask.id] && (
                  <div className="mb-4 inline-flex items-center gap-2 rounded-full bg-emerald-400/15 px-3 py-1.5 text-xs font-bold text-emerald-300">
                    <span className="h-2 w-2 animate-pulse rounded-full bg-emerald-300" />
                    Active since{" "}
                    {formatStartedAt(
                      activeExecutions[currentTask.id].actual_start_time,
                    )}
                  </div>
                )}
                <h3 className="break-words text-2xl font-bold leading-tight">
                  {currentTask.title}
                </h3>
                <p className="mt-3 text-sm text-slate-300">
                  {formatTaskTime(currentTask.planned_start_time)} ·{" "}
                  {currentTask.planned_duration_min} min
                </p>
                <div className="mt-6 grid grid-cols-2 gap-3">
                  <button
                    className="min-h-14 rounded-2xl bg-white px-3 text-base font-bold text-slate-950 transition hover:bg-slate-100 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-300"
                    disabled={
                      Boolean(activeExecutions[currentTask.id]) ||
                      startingTaskId === currentTask.id
                    }
                    onClick={() => void handleStart(currentTask)}
                    type="button"
                  >
                    {startingTaskId === currentTask.id
                      ? "Starting…"
                      : activeExecutions[currentTask.id]
                        ? "In progress"
                        : "Start"}
                  </button>
                  <button
                    className="min-h-14 rounded-2xl border border-white/25 bg-white/10 px-3 text-base font-bold text-white transition hover:bg-white/20"
                    onClick={() => openOutcome(currentTask)}
                    type="button"
                  >
                    Finish
                  </button>
                </div>
              </div>
            ) : (
              <div className="rounded-3xl border border-dashed border-slate-300 bg-white px-5 py-8 text-center">
                <p className="text-lg font-bold">No plans left today</p>
                <p className="mt-2 text-sm text-slate-500">
                  Add a plan and it will appear here.
                </p>
              </div>
            )}
          </section>

          <button
            className="mt-4 flex min-h-14 w-full items-center justify-center gap-2 rounded-2xl border-2 border-slate-950 bg-white px-4 text-base font-bold text-slate-950 transition hover:bg-slate-100"
            onClick={() => setQuickAddOpen(true)}
            type="button"
          >
            <span
              aria-hidden="true"
              className="text-2xl font-light leading-none"
            >
              +
            </span>
            Quick Add
          </button>

          <Link href="/dashboard/habits" className="btn-secondary mt-3 w-full">
            View or reschedule plans
          </Link>
          <section className="mt-7" aria-labelledby="remaining-plan-title">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-lg font-bold" id="remaining-plan-title">
                Remaining today
              </h2>
              {loadError && (
                <button
                  className="min-h-11 rounded-xl px-3 text-xs font-bold text-rose-700 hover:bg-rose-50"
                  onClick={() => void loadToday()}
                  type="button"
                >
                  Refresh failed · Retry
                </button>
              )}
            </div>

            {remainingTasks.length === 0 ? (
              <p className="rounded-2xl bg-white px-4 py-5 text-center text-sm text-slate-500">
                No other plans remain.
              </p>
            ) : (
              <ul className="space-y-3">
                {remainingTasks.map((task) => {
                  const active = activeExecutions[task.id];
                  return (
                    <li
                      className="rounded-2xl border border-slate-200 bg-white p-4"
                      key={task.id}
                    >
                      <div className="flex min-w-0 items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="truncate font-bold text-slate-900">
                            {task.title}
                          </p>
                          <p className="mt-1 text-xs font-medium text-slate-500">
                            {formatTaskTime(task.planned_start_time)} ·{" "}
                            {task.planned_duration_min} min
                          </p>
                        </div>
                        {active && (
                          <span className="shrink-0 rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-bold text-emerald-800">
                            In progress
                          </span>
                        )}
                      </div>
                      <div className="mt-3 grid grid-cols-2 gap-2">
                        <button
                          className="min-h-11 rounded-xl bg-slate-100 px-3 text-sm font-bold text-slate-800 disabled:text-slate-400"
                          disabled={
                            Boolean(active) || startingTaskId === task.id
                          }
                          onClick={() => void handleStart(task)}
                          type="button"
                        >
                          {active
                            ? "In progress"
                            : startingTaskId === task.id
                              ? "Starting…"
                              : "Start"}
                        </button>
                        <button
                          className="min-h-11 rounded-xl bg-slate-950 px-3 text-sm font-bold text-white"
                          onClick={() => openOutcome(task)}
                          type="button"
                        >
                          Log outcome
                        </button>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </>
      )}

      {toast && (
        <div
          aria-live="polite"
          className={`fixed left-1/2 top-[max(1rem,env(safe-area-inset-top))] z-[60] w-[calc(100%-2rem)] max-w-md -translate-x-1/2 rounded-2xl px-4 py-3 text-center text-sm font-bold shadow-xl ${
            toast.tone === "success"
              ? "bg-emerald-600 text-white"
              : "bg-rose-600 text-white"
          }`}
          role={toast.tone === "error" ? "alert" : "status"}
        >
          {toast.message}
        </div>
      )}

      {quickAddOpen && (
        <QuickAddForm onDismiss={closeQuickAdd} onSubmit={handleQuickAdd} />
      )}
      {selectedTask && (
        <OutcomeSheet
          error={outcomeError}
          isActive={Boolean(activeExecutions[selectedTask.id])}
          onDismiss={() => {
            if (!outcomeSaving) setSelectedTask(null);
          }}
          onSelect={handleOutcome}
          saving={outcomeSaving}
          task={selectedTask}
        />
      )}
    </section>
  );
}
