"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "@/app/providers";
import {
  completeExecution,
  createMobileAIOutcome,
  createTask,
  ensureAIPlan,
  getActiveExecutions,
  getTasks,
  predictAIPlan,
  startExecution,
  type Execution,
  type Prediction,
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
import { useDataRefresh } from "@/lib/refresh";
import { useToast } from "@/components/ui/toast";
import OutcomeSheet, {
  type MobileResult,
  type OutcomeTimes,
} from "@/components/mobile/outcome-sheet";
import QuickAddForm from "@/components/mobile/quick-add-form";

function sortTasks(left: Task, right: Task) {
  return taskTimeInMinutes(left.planned_start_time) - taskTimeInMinutes(right.planned_start_time);
}

function startOfWeek(date: Date) {
  const result = new Date(date);
  const offset = (result.getDay() + 6) % 7;
  result.setDate(result.getDate() - offset);
  result.setHours(12, 0, 0, 0);
  return result;
}

function weekDates() {
  const start = startOfWeek(new Date());
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return date;
  });
}

function formatMinutes(minutes: number) {
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

function formatSuccessProbability(probability: number) {
  return `${Math.round(Math.max(0, Math.min(1, probability)) * 100)}%`;
}

function taskStatusLabel(task: Task, active: boolean) {
  if (active) return "In progress";
  if (task.task_status === "success") return "Completed";
  if (task.task_status === "failed") return "Not completed";
  return "Planned";
}

export default function DesktopCommandCenter() {
  const { displayName } = useAuth();
  const notifications = useToast();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [active, setActive] = useState<Record<string, Execution>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [quickAdd, setQuickAdd] = useState(false);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [startingId, setStartingId] = useState<string | null>(null);
  const [savingOutcome, setSavingOutcome] = useState(false);
  const [outcomeError, setOutcomeError] = useState<string | null>(null);
  const [aiPredictions, setAiPredictions] = useState<Record<string, Prediction>>({});
  const [aiLoading, setAiLoading] = useState(false);
  const today = localDateString();

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [allTasks, executions] = await Promise.all([
        getTasks(),
        getActiveExecutions(),
      ]);
      setTasks(allTasks);
      setActive(
        executions.reduce<Record<string, Execution>>((result, execution) => {
          if (!result[execution.task_id]) result[execution.task_id] = execution;
          return result;
        }, {}),
      );
    } catch {
      setError("We couldn’t load your plans. Check the backend connection and try again.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => void load(), [load]);
  useDataRefresh(load);

  const todayTasks = useMemo(
    () => tasks.filter((task) => task.planned_date === today).sort(sortTasks),
    [tasks, today],
  );
  const pending = todayTasks.filter((task) => task.task_status === "pending");
  const completed = todayTasks.filter((task) => task.task_status === "success").length;
  const plannedMinutes = todayTasks.reduce((sum, task) => sum + task.planned_duration_min, 0);
  const activeTask = pending.find((task) => active[task.id]);
  const now = new Date();
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  const nextTask =
    activeTask ??
    pending.find((task) => taskTimeInMinutes(task.planned_start_time) >= nowMinutes) ??
    pending[0] ??
    null;
  const days = useMemo(weekDates, []);
  const weekStart = localDateString(days[0]);
  const weekEnd = localDateString(days[6]);
  const weekTasks = tasks.filter(
    (task) => task.planned_date >= weekStart && task.planned_date <= weekEnd,
  );
  const weekFinished = weekTasks.filter((task) => task.task_status !== "pending");
  const weekCompleted = weekFinished.filter((task) => task.task_status === "success").length;

  useEffect(() => {
    let cancelled = false;
    const eligible = todayTasks.filter((task) => task.task_status === "pending");
    if (!eligible.length) {
      setAiPredictions({});
      setAiLoading(false);
      return;
    }
    setAiLoading(true);
    void Promise.allSettled(
      eligible.map(async (task) => {
        const planId = task.ai_plan_input_id ?? (await ensureAIPlan(task));
        const prediction = await predictAIPlan(planId);
        return [task.id, planId, prediction] as const;
      }),
    ).then((results) => {
      if (cancelled) return;
      setAiPredictions(
        results.reduce<Record<string, Prediction>>((byTask, result) => {
          if (result.status === "fulfilled") {
            byTask[result.value[0]] = result.value[2];
          }
          return byTask;
        }, {}),
      );
      const planIds = new Map(
        results
          .filter((result) => result.status === "fulfilled")
          .map((result) => [result.value[0], result.value[1]]),
      );
      if (planIds.size) {
        setTasks((current) =>
          current.map((task) => {
            const planId = planIds.get(task.id);
            return planId && !task.ai_plan_input_id
              ? { ...task, ai_plan_input_id: planId }
              : task;
          }),
        );
      }
      setAiLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, [todayTasks]);

  const aiAssessment = useMemo(() => {
    const assessed = pending
      .map((task) => ({ task, prediction: aiPredictions[task.id] }))
      .filter(
        (item): item is { task: Task; prediction: Prediction } =>
          Boolean(item.prediction),
      )
      .sort(
        (left, right) =>
          left.prediction.success_probability - right.prediction.success_probability,
      );
    return assessed[0] ?? null;
  }, [aiPredictions, pending]);

  const brief = useMemo(() => {
    if (todayTasks.length === 0) {
      return {
        eyebrow: "A clear page",
        title: "Shape the day around one meaningful plan.",
        detail: "Start with a focused block you can realistically finish. You can build from there.",
      };
    }
    if (activeTask) {
      return {
        eyebrow: "Protect your focus",
        title: `Stay with ${activeTask.title}.`,
        detail: `You marked this plan in progress. Finish or record an outcome before switching context.`,
      };
    }
    if (aiAssessment) {
      const action = aiAssessment.prediction.recommended_actions?.[0];
      return {
        eyebrow: "Personalized recommendation",
        title: `${aiAssessment.task.title} needs the most preparation.`,
        detail:
          action?.detail ??
          "This plan may need more preparation than your other plans today. Review its scope and timing before you begin.",
        actionTitle: action?.title,
        source: "ai-v2" as const,
      };
    }
    if (nextTask) {
      const crowded = plannedMinutes > 360;
      return {
        eyebrow: crowded ? "An ambitious day" : "Your next best move",
        title: `${nextTask.title} at ${formatTaskTime(nextTask.planned_start_time)}.`,
        detail: crowded
          ? `You planned ${formatMinutes(plannedMinutes)} today. Keep some buffer between demanding blocks.`
          : `A ${nextTask.planned_duration_min}-minute block is next. Clear the first small step before it begins.`,
        source: "rules" as const,
      };
    }
    return {
      eyebrow: "Day complete",
      title: "Everything planned for today has an outcome.",
      detail: "Take a moment to review what worked before planning tomorrow.",
      source: "rules" as const,
    };
  }, [activeTask, aiAssessment, nextTask, plannedMinutes, todayTasks.length]);

  async function handleQuickAdd(draft: QuickAddDraft) {
    const count = tasks.filter((task) => task.planned_date === draft.plannedDate).length;
    const created = await createTask(toQuickTaskCreate(draft, count + 1));
    setTasks((current) => [...current, created]);
    setQuickAdd(false);
    notifications.success("Plan added", `${created.title} is now on your timeline.`);
  }

  async function ensureStarted(task: Task) {
    if (active[task.id]) return active[task.id];
    const execution = await startExecution(task.id);
    setActive((current) => ({ ...current, [task.id]: execution }));
    return execution;
  }

  async function handleStart(task: Task) {
    if (startingId || active[task.id]) return;
    setStartingId(task.id);
    try {
      await ensureStarted(task);
      notifications.success("Focus block started", task.title);
    } catch {
      notifications.error("Couldn’t start this plan", "Check your connection and try again.");
    } finally {
      setStartingId(null);
    }
  }

  async function handleOutcome(
    result: MobileResult,
    reason?: FailureReasonCode,
    times?: OutcomeTimes,
  ) {
    if (!selectedTask || savingOutcome) return;
    setSavingOutcome(true);
    setOutcomeError(null);
    try {
      const execution = await ensureStarted(selectedTask);
      if (result === "in_progress") {
        setSelectedTask(null);
        notifications.info("Plan kept in progress", selectedTask.title);
        return;
      }
      const taskStatus = result === "completed" ? "success" : "failed";
      const completedExecution = await completeExecution(execution.id, {
        ...times,
        task_status: taskStatus,
        stopped_early: result !== "completed",
        interruption_count: 0,
        failure_reason: reason,
      });
      const finishedTask = selectedTask;
      setTasks((current) =>
        current.map((task) =>
          task.id === finishedTask.id ? { ...task, task_status: taskStatus } : task,
        ),
      );
      setActive((current) => {
        const next = { ...current };
        delete next[finishedTask.id];
        return next;
      });
      setSelectedTask(null);
      notifications.success("Outcome saved", finishedTask.title);
      void createMobileAIOutcome({
        task: finishedTask,
        execution: completedExecution,
        outcomeStatus: result,
        failureReason: reason,
      }).catch(() =>
        notifications.warn(
          "Outcome saved",
          "AI learning could not update this time. Your plan record is safe.",
        ),
      );
    } catch {
      setOutcomeError("We couldn’t save this outcome. Check your connection and try again.");
    } finally {
      setSavingOutcome(false);
    }
  }

  const formattedDate = new Date(`${today}T12:00:00`).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
  const greeting = now.getHours() < 12 ? "Good morning" : now.getHours() < 18 ? "Good afternoon" : "Good evening";

  return (
    <div className="space-y-6 pb-8 text-slate-950">
      <section className="desktop-hero relative overflow-hidden rounded-[2rem] bg-slate-950 px-8 py-9 text-white shadow-2xl shadow-slate-300/60 xl:px-10">
        <div className="desktop-hero-glow desktop-hero-glow-one" />
        <div className="desktop-hero-glow desktop-hero-glow-two" />
        <div className="relative z-10 flex items-end justify-between gap-8">
          <div className="max-w-3xl">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-300">{formattedDate}</p>
            <h1 className="mt-4 text-4xl font-semibold tracking-[-0.04em] xl:text-5xl">
              {greeting}, {displayName}.
            </h1>
            <p className="mt-4 max-w-2xl text-lg leading-relaxed text-slate-300">
              {todayTasks.length === 0
                ? "Your day is open. Give it one clear direction."
                : `${todayTasks.length} plans · ${formatMinutes(plannedMinutes)} scheduled · ${pending.length} remaining`}
            </p>
          </div>
          <div className="flex shrink-0 gap-3">
            <button className="rounded-xl border border-white/20 bg-white/10 px-5 py-3 text-sm font-semibold text-white backdrop-blur transition hover:bg-white/20" onClick={() => window.dispatchEvent(new Event("habittrace:open-coach"))}>
              Ask coach
            </button>
            <button className="rounded-xl bg-white px-5 py-3 text-sm font-bold text-slate-950 transition hover:bg-emerald-100" onClick={() => setQuickAdd(true)}>
              + Add plan
            </button>
          </div>
        </div>
        <div className="relative z-10 mt-9 grid max-w-2xl grid-cols-3 gap-3">
          {[
            ["Completed", `${completed}/${todayTasks.length || 0}`],
            ["Remaining", String(pending.length)],
            ["Planned time", formatMinutes(plannedMinutes)],
          ].map(([label, value]) => (
            <div key={label} className="rounded-2xl border border-white/10 bg-white/[0.07] px-4 py-3 backdrop-blur-sm">
              <p className="text-xl font-bold">{value}</p>
              <p className="mt-1 text-xs font-medium text-slate-400">{label}</p>
            </div>
          ))}
        </div>
      </section>

      {error && (
        <div role="alert" className="flex items-center justify-between rounded-2xl border border-rose-200 bg-rose-50 px-5 py-4 text-sm text-rose-900">
          <span>{error}</span>
          <button className="font-bold underline underline-offset-4" onClick={() => void load()}>Retry</button>
        </div>
      )}

      <div className="grid grid-cols-[minmax(0,1.75fr)_minmax(18rem,1fr)] gap-6">
        <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm" aria-labelledby="timeline-title">
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.16em] text-slate-400">Today</p>
              <h2 id="timeline-title" className="mt-1 text-2xl font-bold tracking-tight">Your timeline</h2>
            </div>
            <Link className="btn-secondary" href="/dashboard/calendar">Open calendar →</Link>
          </div>

          {loading && tasks.length === 0 ? (
            <div className="mt-7 space-y-4" role="status">
              {[1, 2, 3].map((item) => <div key={item} className="h-20 animate-pulse rounded-2xl bg-slate-100" />)}
            </div>
          ) : todayTasks.length === 0 ? (
            <button onClick={() => setQuickAdd(true)} className="mt-7 grid min-h-64 w-full place-items-center rounded-2xl border border-dashed border-slate-300 bg-slate-50 text-center transition hover:border-slate-400 hover:bg-white">
              <span>
                <span className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-slate-950 text-2xl text-white">+</span>
                <span className="mt-4 block text-lg font-bold">Create your first plan</span>
                <span className="mt-1 block text-sm text-slate-500">Give today one clear point of focus.</span>
              </span>
            </button>
          ) : (
            <ol className="relative mt-7 space-y-1 before:absolute before:bottom-8 before:left-[5.45rem] before:top-8 before:w-px before:bg-slate-200">
              {todayTasks.map((task) => {
                const inProgress = Boolean(active[task.id]);
                const isNext = nextTask?.id === task.id;
                return (
                  <li key={task.id} className="relative grid grid-cols-[4.5rem_1.5rem_minmax(0,1fr)] items-center gap-3 py-2">
                    <time className="text-right text-sm font-semibold text-slate-500">{formatTaskTime(task.planned_start_time)}</time>
                    <span className={`relative z-10 mx-auto h-3 w-3 rounded-full ring-4 ring-white ${inProgress ? "animate-pulse bg-emerald-500" : task.task_status === "success" ? "bg-slate-950" : task.task_status === "failed" ? "bg-rose-300" : "bg-slate-300"}`} />
                    <article className={`group rounded-2xl border p-4 transition ${isNext ? "border-slate-900 bg-slate-950 text-white shadow-lg shadow-slate-200" : "border-slate-200 bg-white hover:border-slate-300 hover:shadow-sm"}`}>
                      <div className="flex items-center justify-between gap-4">
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <h3 className="truncate font-bold">{task.title}</h3>
                            {isNext && <span className="rounded-full bg-emerald-400/15 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-emerald-300">{inProgress ? "Active" : "Up next"}</span>}
                            {aiPredictions[task.id] && (
                              <span
                                className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${isNext ? "bg-emerald-400/15 text-emerald-300" : "bg-emerald-50 text-emerald-700"}`}
                                title="Experimental estimate based on the information available when this plan was created"
                              >
                                Estimated success {formatSuccessProbability(aiPredictions[task.id].success_probability)}
                              </span>
                            )}
                          </div>
                          <p className={`mt-1 text-xs ${isNext ? "text-slate-400" : "text-slate-500"}`}>{task.task_category} · {task.planned_duration_min} min · {taskStatusLabel(task, inProgress)}</p>
                          {aiPredictions[task.id]?.personalization?.applied && (
                            <p className={`mt-1 text-[11px] ${isNext ? "text-emerald-300/80" : "text-emerald-700"}`}>
                              Personalized using {aiPredictions[task.id].personalization!.sample_count} previous plans
                            </p>
                          )}
                        </div>
                        {task.task_status === "pending" && (
                          <div className="flex shrink-0 gap-2">
                            <button disabled={inProgress || startingId === task.id} onClick={() => void handleStart(task)} className={`rounded-lg px-3 py-2 text-xs font-bold ${isNext ? "bg-white text-slate-950 disabled:bg-slate-700 disabled:text-slate-400" : "bg-slate-100 text-slate-800"}`}>
                              {inProgress ? "Started" : startingId === task.id ? "Starting…" : "Start"}
                            </button>
                            <button onClick={() => { setOutcomeError(null); setSelectedTask(task); }} className={`rounded-lg px-3 py-2 text-xs font-bold ${isNext ? "bg-white/10 text-white hover:bg-white/20" : "bg-slate-950 text-white"}`}>Outcome</button>
                          </div>
                        )}
                      </div>
                    </article>
                  </li>
                );
              })}
            </ol>
          )}
        </section>

        <div className="space-y-6">
          <section className="overflow-hidden rounded-3xl bg-emerald-50 p-6 ring-1 ring-emerald-100" aria-labelledby="brief-title">
            <div className="flex items-center justify-between">
              <span className="grid h-10 w-10 place-items-center rounded-2xl bg-emerald-600 font-bold text-white">✦</span>
              <span className="text-[10px] font-bold uppercase tracking-[0.16em] text-emerald-700">
                {brief.source === "ai-v2"
                  ? "Personalized recommendation · Experimental"
                  : aiLoading
                    ? "Preparing personalized recommendations"
                    : "Schedule-based guidance"}
              </span>
            </div>
            <p className="mt-6 text-xs font-bold uppercase tracking-[0.16em] text-emerald-700">{brief.eyebrow}</p>
            <h2 id="brief-title" className="mt-2 text-2xl font-bold leading-tight tracking-tight text-slate-950">{brief.title}</h2>
            <p className="mt-3 text-sm leading-relaxed text-slate-600">{brief.detail}</p>
            {brief.actionTitle && (
              <p className="mt-4 rounded-xl bg-white/70 px-3 py-2 text-sm font-semibold text-emerald-950 ring-1 ring-emerald-100">
                Recommendation: {brief.actionTitle}
              </p>
            )}
            {brief.source === "ai-v2" && (
              <p className="mt-3 text-[11px] leading-relaxed text-emerald-900/65">
                Estimates are experimental planning guidance and are not yet validated
                as personal success probabilities.
              </p>
            )}
            <div className="mt-6 flex gap-2">
              <Link href="/dashboard/scheduler" className="rounded-xl bg-emerald-700 px-4 py-2.5 text-sm font-bold text-white hover:bg-emerald-800">Review schedule</Link>
              <button onClick={() => window.dispatchEvent(new Event("habittrace:open-coach"))} className="rounded-xl bg-white px-4 py-2.5 text-sm font-bold text-emerald-900 ring-1 ring-emerald-200">Ask coach</button>
            </div>
          </section>

          <section className="rounded-3xl border border-slate-200 bg-white p-6 shadow-sm" aria-labelledby="week-title">
            <div className="flex items-end justify-between gap-4">
              <div>
                <p className="text-xs font-bold uppercase tracking-[0.16em] text-slate-400">Rhythm</p>
                <h2 id="week-title" className="mt-1 text-xl font-bold">This week</h2>
              </div>
              <p className="text-right text-sm font-semibold text-slate-700">{weekFinished.length ? `${weekCompleted}/${weekFinished.length} completed` : "No outcomes yet"}</p>
            </div>
            <div className="mt-6 grid grid-cols-7 gap-2">
              {days.map((day) => {
                const date = localDateString(day);
                const dayTasks = weekTasks.filter((task) => task.planned_date === date);
                const done = dayTasks.filter((task) => task.task_status === "success").length;
                const pastOutcomes = dayTasks.filter((task) => task.task_status !== "pending").length;
                const isToday = date === today;
                return (
                  <div key={date} className="text-center">
                    <p className="text-[10px] font-bold uppercase text-slate-400">{day.toLocaleDateString("en-US", { weekday: "narrow" })}</p>
                    <div title={`${done} completed of ${dayTasks.length} planned`} className={`mx-auto mt-2 grid h-9 w-9 place-items-center rounded-xl text-xs font-bold ${isToday ? "ring-2 ring-slate-950 ring-offset-2" : ""} ${pastOutcomes && done === pastOutcomes ? "bg-emerald-500 text-white" : pastOutcomes ? "bg-amber-100 text-amber-900" : dayTasks.length ? "bg-slate-100 text-slate-600" : "bg-slate-50 text-slate-300"}`}>
                      {day.getDate()}
                    </div>
                  </div>
                );
              })}
            </div>
            <p className="mt-5 text-xs leading-relaxed text-slate-500">Green means every recorded outcome was completed. Amber means a mixed day. Future plans stay neutral.</p>
          </section>
        </div>
      </div>

      {quickAdd && <QuickAddForm onDismiss={() => setQuickAdd(false)} onSubmit={handleQuickAdd} />}
      {selectedTask && (
        <OutcomeSheet
          task={selectedTask}
          isActive={Boolean(active[selectedTask.id])}
          error={outcomeError}
          saving={savingOutcome}
          onDismiss={() => { if (!savingOutcome) setSelectedTask(null); }}
          onSelect={handleOutcome}
        />
      )}
    </div>
  );
}
