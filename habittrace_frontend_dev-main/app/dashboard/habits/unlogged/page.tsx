"use client";

import { useCallback, useEffect, useState } from "react";
import {
  createMobileAIOutcome,
  getActiveExecutions,
  getTasks,
  logExecution,
  startExecution,
  type Execution,
  type Task,
} from "@/lib/api";
import {
  formatTaskTime,
  type FailureReasonCode,
} from "@/lib/mobile-task";
import {
  filterUnloggedPastPlans,
  formatUnloggedDate,
} from "@/lib/unlogged";
import { useDataRefresh } from "@/lib/refresh";
import { useToast } from "@/components/ui/toast";
import OutcomeSheet, {
  type MobileResult,
  type OutcomeTimes,
} from "@/components/mobile/outcome-sheet";

function toTwentyFourHour(time: string): string {
  const match = time.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);
  if (!match) return "12:00";
  let hour = Number(match[1]);
  const minute = match[2];
  const meridiem = match[3]?.toUpperCase();
  if (meridiem === "AM" && hour === 12) hour = 0;
  if (meridiem === "PM" && hour !== 12) hour += 12;
  return `${String(hour).padStart(2, "0")}:${minute}`;
}

function plannedWindowIso(task: Task): { start: string; end: string } {
  const start = new Date(
    `${task.planned_date}T${toTwentyFourHour(task.planned_start_time)}:00`,
  );
  const end = new Date(start.getTime() + task.planned_duration_min * 60_000);
  return { start: start.toISOString(), end: end.toISOString() };
}

export default function UnloggedPlansPage() {
  const toast = useToast();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [logging, setLogging] = useState<Task | null>(null);
  const [active, setActive] = useState<Record<string, Execution>>({});
  const [outcomeError, setOutcomeError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(false);
    try {
      const [list, executions] = await Promise.all([
        getTasks(),
        getActiveExecutions(),
      ]);
      setTasks(list);
      setActive(Object.fromEntries(executions.map((e) => [e.task_id, e])));
    } catch {
      setError(true);
      setTasks([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);
  useDataRefresh(load);

  const reviewList = filterUnloggedPastPlans(tasks);

  async function markNotCompleted(task: Task) {
    if (busyId) return;
    setBusyId(task.id);
    try {
      const { start, end } = plannedWindowIso(task);
      await logExecution({
        task_id: task.id,
        actual_start_time: start,
        actual_end_time: end,
        interruption_count: 0,
        stopped_early: true,
        task_status: "failed",
        failure_reason: "other",
      });
      toast.success("Marked not completed", `"${task.title}" was logged.`);
      void load();
    } catch {
      toast.error("Couldn’t save", "Please try again.");
    } finally {
      setBusyId(null);
    }
  }

  async function finish(
    result: MobileResult,
    reason?: FailureReasonCode,
    times?: OutcomeTimes,
  ) {
    if (!logging || busyId) return;
    setBusyId(logging.id);
    setOutcomeError(null);
    try {
      if (result === "in_progress") {
        await startExecution(logging.id);
        setLogging(null);
        toast.success("Plan kept active");
        void load();
        return;
      }
      const { start, end } = plannedWindowIso(logging);
      const execution = await logExecution({
        task_id: logging.id,
        actual_start_time: times?.actual_start_time ?? start,
        actual_end_time: times?.actual_end_time ?? end,
        interruption_count: 0,
        stopped_early: result !== "completed",
        task_status: result === "completed" ? "success" : "failed",
        failure_reason: reason,
      });
      try {
        await createMobileAIOutcome({
          task: logging,
          execution,
          outcomeStatus: result,
          failureReason: reason,
        });
      } catch {
        toast.warn("Outcome saved", "AI learning could not update this time.");
      }
      setLogging(null);
      toast.success("Outcome recorded");
      void load();
    } catch {
      setOutcomeError("Couldn’t save this outcome. Please try again.");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-4 pb-6">
      <header className="rounded-2xl border border-rose-100 bg-gradient-to-r from-rose-50 via-white to-amber-50 px-4 py-4 shadow-sm sm:px-5">
        <h1 className="text-2xl font-bold tracking-tight text-slate-950">
          Unlogged plans
        </h1>
        <p className="mt-1 max-w-2xl text-sm text-slate-600">
          These past plans still need an outcome. Log what happened, or mark
          them as not completed.
        </p>
      </header>

      {loading && (
        <p role="status" className="text-sm text-slate-500">
          Loading unlogged plans…
        </p>
      )}
      {error && (
        <div
          role="alert"
          className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
        >
          Couldn’t load unlogged plans.{" "}
          <button className="font-bold underline" onClick={() => void load()}>
            Retry
          </button>
        </div>
      )}
      {!loading && !error && reviewList.length === 0 && (
        <div className="rounded-2xl border border-dashed border-slate-200 bg-white px-6 py-12 text-center">
          <p className="text-lg font-bold text-slate-950">You&apos;re caught up</p>
          <p className="mt-2 text-sm text-slate-500">
            There are no past plans waiting for a log.
          </p>
        </div>
      )}
      {reviewList.length > 0 && (
        <ul className="space-y-3">
          {reviewList.map((task) => (
            <li
              key={task.id}
              className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs font-bold uppercase tracking-wide text-rose-700">
                    {formatUnloggedDate(task.planned_date)}
                  </p>
                  <h2 className="mt-1 break-words text-lg font-bold text-slate-950">
                    {task.title}
                  </h2>
                  <p className="mt-1 text-sm text-slate-500">
                    {formatTaskTime(task.planned_start_time)} ·{" "}
                    {task.planned_duration_min} min · {task.task_category}
                  </p>
                  {task.notes?.trim() && (
                    <p className="mt-2 whitespace-pre-wrap text-sm leading-relaxed text-slate-600">
                      {task.notes.trim()}
                    </p>
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  <button
                    className="btn-secondary"
                    disabled={busyId === task.id}
                    onClick={() => void markNotCompleted(task)}
                  >
                    Mark not completed
                  </button>
                  <button
                    className="btn-primary"
                    disabled={busyId === task.id}
                    onClick={() => {
                      setOutcomeError(null);
                      setLogging(task);
                    }}
                  >
                    Log outcome
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}

      {logging && (
        <OutcomeSheet
          task={logging}
          isActive={!!active[logging.id]}
          saving={busyId === logging.id}
          error={outcomeError}
          onDismiss={() => setLogging(null)}
          onSelect={finish}
        />
      )}
    </div>
  );
}
