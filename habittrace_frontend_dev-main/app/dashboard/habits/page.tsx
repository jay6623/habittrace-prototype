"use client";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import {
  createTask,
  getTasks,
  updateTask,
  deleteTask,
  reviseAIPlan,
  clearAIPlan,
  startExecution,
  completeExecution,
  getActiveExecutions,
  createMobileAIOutcome,
  type Task,
  type Execution,
} from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";
import {
  localDateString,
  taskTimeInMinutes,
  toQuickTaskCreate,
  TASK_CATEGORIES,
  type QuickAddDraft,
  type FailureReasonCode,
} from "@/lib/mobile-task";
import QuickAddForm from "@/components/mobile/quick-add-form";
import OutcomeSheet, {
  type MobileResult,
  type OutcomeTimes,
} from "@/components/mobile/outcome-sheet";
import Dialog from "@/components/ui/dialog";
import { useToast } from "@/components/ui/toast";

export default function PlansPage() {
  return (
    <Suspense fallback={<p role="status">Loading plans…</p>}>
      <Plans />
    </Suspense>
  );
}
function Plans() {
  const params = useSearchParams();
  const toast = useToast();
  const [date, setDate] = useState(localDateString);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [active, setActive] = useState<Record<string, Execution>>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [editing, setEditing] = useState<Task | "new" | null>(null);
  const [removing, setRemoving] = useState<Task | null>(null);
  const [outcome, setOutcome] = useState<Task | null>(null);
  const [outcomeError, setOutcomeError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [filter, setFilter] = useState("all");
  const request = useRef(0);
  const load = useCallback(async () => {
    const id = ++request.current;
    setLoading(true);
    setError(false);
    try {
      const [list, executions] = await Promise.all([
        getTasks(date),
        getActiveExecutions(),
      ]);
      if (id !== request.current) return;
      setTasks(
        list.sort(
          (a, b) =>
            taskTimeInMinutes(a.planned_start_time) -
            taskTimeInMinutes(b.planned_start_time),
        ),
      );
      setActive(Object.fromEntries(executions.map((e) => [e.task_id, e])));
    } catch {
      if (id === request.current) {
        setError(true);
        setTasks([]);
      }
    } finally {
      if (id === request.current) setLoading(false);
    }
  }, [date]);
  useEffect(() => {
    void load();
  }, [load]);
  useDataRefresh(load);
  useEffect(() => {
    const value = params.get("date");
    if (
      value &&
      /^\d{4}-\d{2}-\d{2}$/.test(value) &&
      !Number.isNaN(Date.parse(value))
    )
      setDate(value);
  }, [params]);
  const selected = params.get("task");
  useEffect(() => {
    if (selected && !loading)
      document
        .getElementById(`plan-${selected}`)
        ?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [selected, loading]);
  function offset(n: number) {
    const d = new Date(`${date}T12:00:00`);
    d.setDate(d.getDate() + n);
    setDate(localDateString(d));
  }
  async function save(draft: QuickAddDraft) {
    const forDate =
      draft.plannedDate === date ? tasks : await getTasks(draft.plannedDate);
    const payload = toQuickTaskCreate(
      draft,
      forDate.length + (editing === "new" ? 1 : 0),
    );
    if (editing && editing !== "new") {
      await updateTask(editing.id, {
        ...payload,
        energy_level: editing.energy_level,
        focus_level: editing.focus_level,
      });
      if (editing.ai_plan_input_id) {
        try {
          await reviseAIPlan(editing.id, editing.ai_plan_input_id, payload);
        } catch {
          clearAIPlan(editing.id);
          toast.warn(
            "Plan saved",
            "AI advice will be unavailable until a new snapshot is created.",
          );
        }
      }
    } else await createTask(payload);
    setEditing(null);
    setDate(draft.plannedDate);
    toast.success("Plan saved");
    void load();
  }
  async function begin(task: Task) {
    if (busy) return;
    setBusy(true);
    try {
      const e = await startExecution(task.id);
      setActive((a) => ({ ...a, [task.id]: e }));
      toast.success("Started", "Your start time was recorded.");
    } catch {
      toast.error("Couldn’t start", "Please try again.");
    } finally {
      setBusy(false);
    }
  }
  async function finish(
    result: MobileResult,
    reason?: FailureReasonCode,
    times?: OutcomeTimes,
  ) {
    if (!outcome || busy) return;
    setBusy(true);
    setOutcomeError(null);
    try {
      const e = active[outcome.id] ?? (await startExecution(outcome.id));
      setActive((a) => ({ ...a, [outcome.id]: e }));
      if (result !== "in_progress") {
        const completed = await completeExecution(e.id, {
          ...times,
          task_status: result === "completed" ? "success" : "failed",
          stopped_early: result !== "completed",
          failure_reason: reason,
        });
        try {
          await createMobileAIOutcome({
            task: outcome,
            execution: completed,
            outcomeStatus: result,
            failureReason: reason,
          });
        } catch {
          toast.warn(
            "Outcome saved",
            "AI learning could not update this time.",
          );
        }
      }
      setOutcome(null);
      toast.success(
        result === "in_progress" ? "Plan kept active" : "Outcome recorded",
      );
      void load();
    } catch {
      setOutcomeError("Couldn’t save this outcome. Please try again.");
    } finally {
      setBusy(false);
    }
  }
  const draft: QuickAddDraft | undefined =
    editing && editing !== "new"
      ? {
          title: editing.title,
          plannedDate: editing.planned_date,
          plannedTime: `${String(Math.floor(taskTimeInMinutes(editing.planned_start_time) / 60)).padStart(2, "0")}:${String(taskTimeInMinutes(editing.planned_start_time) % 60).padStart(2, "0")}`,
          durationMinutes: editing.planned_duration_min,
          category: TASK_CATEGORIES.includes(
            editing.task_category as QuickAddDraft["category"],
          )
            ? (editing.task_category as QuickAddDraft["category"])
            : "Other",
          importance: editing.importance,
        }
      : undefined;
  const visible = tasks.filter(
    (t) => filter === "all" || t.task_status === filter || t.id === selected,
  );
  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Your plans</h1>
          <p className="mt-2 text-sm text-slate-500">
            Make a little room for what matters today.
          </p>
        </div>
        <button className="btn-primary" onClick={() => setEditing("new")}>
          + Add plan
        </button>
      </header>
      <div className="flex flex-wrap items-center gap-2">
        <button
          className="btn-secondary"
          aria-label="Previous day"
          onClick={() => offset(-1)}
        >
          ←
        </button>
        <input
          aria-label="Plan date"
          className="field !w-auto"
          type="date"
          value={date}
          onChange={(e) => {
            if (e.target.value) setDate(e.target.value);
          }}
        />
        <button
          className="btn-secondary"
          aria-label="Next day"
          onClick={() => offset(1)}
        >
          →
        </button>
        <button
          className="btn-secondary"
          onClick={() => setDate(localDateString())}
        >
          Today
        </button>
        <select
          aria-label="Filter plans by status"
          className="field !w-auto sm:ml-auto"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        >
          <option value="all">All plans</option>
          <option value="pending">Planned</option>
          <option value="success">Completed</option>
          <option value="failed">Not completed</option>
        </select>
      </div>
      {loading ? (
        <p role="status" className="panel">
          Loading plans…
        </p>
      ) : error ? (
        <div role="alert" className="panel">
          <p>Couldn’t load plans for this date.</p>
          <button onClick={() => void load()} className="btn-secondary mt-3">
            Try again
          </button>
        </div>
      ) : visible.length === 0 ? (
        <div className="panel py-12 text-center">
          <h2 className="text-xl font-semibold">
            {tasks.length ? "No plans match this filter" : "A fresh start"}
          </h2>
          <p className="my-3 text-slate-500">
            {tasks.length
              ? "Choose another status to see your plans."
              : "Add one small plan. You can adjust it as your day changes."}
          </p>
          <button className="btn-primary" onClick={() => setEditing("new")}>
            Add a plan
          </button>
        </div>
      ) : (
        <ul className="space-y-4">
          {visible.map((task) => (
            <li
              id={`plan-${task.id}`}
              key={task.id}
              className={`panel scroll-mt-28 ${selected === task.id ? "ring-2 ring-sky-500" : ""}`}
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="mb-1 text-sm text-slate-500">
                    {task.planned_start_time} · {task.planned_duration_min} min
                    · {task.task_category}
                  </p>
                  <h2 className="break-words text-xl font-semibold">
                    {task.title}
                  </h2>
                </div>
                <span
                  className={`rounded-full px-3 py-1 text-xs font-semibold ${task.task_status === "success" ? "bg-emerald-50 text-emerald-800" : "bg-slate-100 text-slate-600"}`}
                >
                  {active[task.id]
                    ? "In progress"
                    : task.task_status === "success"
                      ? "Completed"
                      : task.task_status === "failed"
                        ? "Not completed"
                        : "Planned"}
                </span>
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {task.task_status === "pending" && (
                  <>
                    <button
                      disabled={busy || !!active[task.id]}
                      className="btn-primary"
                      onClick={() => void begin(task)}
                    >
                      {active[task.id] ? "In progress" : "Start"}
                    </button>
                    <button
                      disabled={busy}
                      className="btn-secondary"
                      onClick={() => {
                        setOutcome(task);
                        setOutcomeError(null);
                      }}
                    >
                      Log outcome
                    </button>
                  </>
                )}
                <button
                  className="btn-secondary"
                  disabled={busy}
                  onClick={() => setEditing(task)}
                >
                  Edit
                </button>
                <Link
                  className="btn-secondary"
                  href={`/dashboard/scheduler?date=${date}&task=${task.id}`}
                >
                  Find a time
                </Link>
                <button
                  className="btn-secondary !text-rose-700 sm:ml-auto"
                  disabled={busy}
                  onClick={() => setRemoving(task)}
                >
                  Delete
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
      {editing && (
        <QuickAddForm
          initialDate={date}
          initialDraft={draft}
          onDismiss={() => setEditing(null)}
          onSubmit={save}
        />
      )}
      {outcome && (
        <OutcomeSheet
          task={outcome}
          isActive={!!active[outcome.id]}
          saving={busy}
          error={outcomeError}
          onDismiss={() => setOutcome(null)}
          onSelect={finish}
        />
      )}
      {removing && (
        <Dialog
          title="Delete this plan?"
          onClose={() => setRemoving(null)}
          busy={busy}
        >
          <p className="mb-5 text-sm">
            “{removing.title}” and its execution records will be removed. This
            cannot be undone.
          </p>
          <div className="flex gap-3">
            <button
              className="btn-secondary"
              disabled={busy}
              onClick={() => setRemoving(null)}
            >
              Keep plan
            </button>
            <button
              className="btn-primary !bg-rose-700"
              disabled={busy}
              onClick={async () => {
                setBusy(true);
                try {
                  await deleteTask(removing.id);
                  setRemoving(null);
                  toast.success("Plan deleted");
                  void load();
                } catch {
                  toast.error("Couldn’t delete the plan", "Please try again.");
                } finally {
                  setBusy(false);
                }
              }}
            >
              Delete plan
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
