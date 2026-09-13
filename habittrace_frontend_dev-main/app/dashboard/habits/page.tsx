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
import LoggedPlanEditForm from "@/components/mobile/logged-plan-edit-form";
import OutcomeSheet, {
  type MobileResult,
  type OutcomeTimes,
} from "@/components/mobile/outcome-sheet";
import Dialog from "@/components/ui/dialog";
import { useToast } from "@/components/ui/toast";

const CATEGORY_STYLES: Record<string, string> = {
  Work: "bg-sky-50 text-sky-700 ring-sky-100",
  Study: "bg-violet-50 text-violet-700 ring-violet-100",
  Chores: "bg-amber-50 text-amber-700 ring-amber-100",
  "Fitness/Health": "bg-emerald-50 text-emerald-700 ring-emerald-100",
  "Errands/Admin": "bg-orange-50 text-orange-700 ring-orange-100",
  "Hobbies/Leisure": "bg-fuchsia-50 text-fuchsia-700 ring-fuchsia-100",
  Social: "bg-cyan-50 text-cyan-700 ring-cyan-100",
  Other: "bg-slate-100 text-slate-600 ring-slate-200",
};

function formatPlannedMinutes(minutes: number) {
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return remainder ? `${hours}h ${remainder}m` : `${hours}h`;
}

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
  const [editingLogged, setEditingLogged] = useState<Task | null>(null);
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
          notes: editing.notes ?? "",
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
  const completedCount = tasks.filter((task) => task.task_status === "success").length;
  const remainingCount = tasks.filter((task) => task.task_status === "pending").length;
  const plannedMinutes = tasks.reduce(
    (total, task) => total + task.planned_duration_min,
    0,
  );
  return (
    <div className="space-y-4 pb-6">
      <header className="overflow-hidden rounded-2xl border border-emerald-100 bg-gradient-to-r from-emerald-50 via-white to-lime-50 shadow-sm">
        <div className="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5">
          <div className="mr-auto min-w-48">
            <h1 className="text-2xl font-bold tracking-tight text-slate-950">Your plans</h1>
            <p className="mt-0.5 text-sm text-emerald-900/65">
              Make room for what matters today.
            </p>
          </div>
          <div className="flex items-center rounded-xl border border-emerald-100 bg-white p-1 shadow-sm">
            <button
              className="grid min-h-9 min-w-9 place-items-center rounded-lg text-slate-500 transition hover:bg-emerald-50 hover:text-emerald-800"
              aria-label="Previous day"
              onClick={() => offset(-1)}
            >
              ←
            </button>
            <input
              aria-label="Plan date"
              className="min-h-9 w-[8.8rem] border-0 bg-transparent px-2 text-sm font-semibold text-slate-800 outline-none"
              type="date"
              value={date}
              onChange={(e) => {
                if (e.target.value) setDate(e.target.value);
              }}
            />
            <button
              className="grid min-h-9 min-w-9 place-items-center rounded-lg text-slate-500 transition hover:bg-emerald-50 hover:text-emerald-800"
              aria-label="Next day"
              onClick={() => offset(1)}
            >
              →
            </button>
          </div>
          <button
            className="min-h-11 rounded-xl border border-emerald-200 bg-white px-4 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50"
            onClick={() => setDate(localDateString())}
          >
            Today
          </button>
          <select
            aria-label="Filter plans by status"
            className="min-h-11 rounded-xl border border-emerald-200 bg-white px-3 text-sm font-semibold text-slate-700 outline-none focus:border-emerald-500"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          >
            <option value="all">All plans</option>
            <option value="pending">Planned</option>
            <option value="success">Completed</option>
            <option value="failed">Not completed</option>
          </select>
          <button
            className="inline-flex min-h-11 items-center justify-center rounded-xl bg-emerald-600 px-4 text-sm font-bold text-white shadow-sm transition hover:bg-emerald-700"
            onClick={() => setEditing("new")}
          >
            + Add plan
          </button>
        </div>
        <div className="grid grid-cols-3 divide-x divide-emerald-100 border-t border-emerald-100 bg-white/65">
          <div className="px-4 py-2.5 sm:px-5">
            <p className="text-lg font-bold text-slate-950">{tasks.length}</p>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">Plans</p>
          </div>
          <div className="px-4 py-2.5 sm:px-5">
            <p className="text-lg font-bold text-slate-950">{formatPlannedMinutes(plannedMinutes)}</p>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">Planned</p>
          </div>
          <div className="px-4 py-2.5 sm:px-5">
            <p className="text-lg font-bold text-emerald-700">{completedCount}/{tasks.length}</p>
            <p className="text-[11px] font-semibold uppercase tracking-wide text-slate-500">
              Completed · {remainingCount} left
            </p>
          </div>
        </div>
      </header>
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
        <div className="rounded-2xl border border-dashed border-emerald-200 bg-emerald-50/50 py-10 text-center">
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
        <ul className="divide-y divide-slate-100 rounded-2xl border border-slate-200 bg-white shadow-sm">
          {visible.map((task) => (
            <li
              id={`plan-${task.id}`}
              key={task.id}
              className={`group relative scroll-mt-28 px-4 py-3.5 transition sm:px-5 ${
                selected === task.id
                  ? "bg-emerald-50/80 ring-2 ring-inset ring-emerald-400"
                  : "hover:bg-slate-50/80"
              }`}
            >
              <div className="grid gap-3 sm:grid-cols-[5.5rem_minmax(0,1fr)_auto] sm:items-center">
                <div className="flex items-center gap-3 sm:block">
                  <p className="text-sm font-bold tabular-nums text-slate-700">
                    {task.planned_start_time}
                  </p>
                  <span
                    aria-hidden="true"
                    className={`mt-1 block h-2.5 w-2.5 rounded-full ring-4 ring-white ${
                      active[task.id]
                        ? "animate-pulse bg-emerald-500"
                        : task.task_status === "success"
                          ? "bg-emerald-400"
                          : task.task_status === "failed"
                            ? "bg-rose-300"
                            : "bg-slate-300"
                    }`}
                  />
                </div>
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="break-words text-base font-bold text-slate-950 sm:text-lg">
                      {task.title}
                    </h2>
                    <span
                      className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ring-1 ring-inset ${
                        CATEGORY_STYLES[task.task_category] ?? CATEGORY_STYLES.Other
                      }`}
                    >
                      {task.task_category}
                    </span>
                  </div>
                  <p className="mt-1 text-xs font-medium text-slate-500">
                    {task.planned_duration_min} min
                  </p>
                  {task.notes?.trim() && (
                    <p className="mt-2 whitespace-pre-wrap text-sm leading-relaxed text-slate-600">
                      {task.notes.trim()}
                    </p>
                  )}
                </div>
                <div className="flex flex-wrap items-center gap-2 sm:justify-end">
                  <span
                    className={`rounded-full px-2.5 py-1 text-xs font-semibold ${
                      active[task.id]
                        ? "bg-emerald-600 text-white"
                        : task.task_status === "success"
                          ? "bg-emerald-100 text-emerald-800"
                          : task.task_status === "failed"
                            ? "bg-rose-50 text-rose-700"
                            : "bg-slate-100 text-slate-600"
                    }`}
                  >
                    {active[task.id]
                      ? "In progress"
                      : task.task_status === "success"
                        ? "Completed"
                        : task.task_status === "failed"
                          ? "Not completed"
                          : "Planned"}
                  </span>
                  {task.task_status === "pending" && (
                    <>
                      <button
                        disabled={busy || !!active[task.id]}
                        className="inline-flex min-h-9 items-center justify-center rounded-lg bg-emerald-600 px-3 text-xs font-bold text-white transition hover:bg-emerald-700 disabled:bg-slate-300"
                        onClick={() => void begin(task)}
                      >
                        {active[task.id] ? "In progress" : "Start"}
                      </button>
                      <button
                        disabled={busy}
                        className="inline-flex min-h-9 items-center justify-center rounded-lg bg-emerald-50 px-3 text-xs font-bold text-emerald-800 transition hover:bg-emerald-100"
                        onClick={() => {
                          setOutcome(task);
                          setOutcomeError(null);
                        }}
                      >
                        Log outcome
                      </button>
                    </>
                  )}
                  <Link
                    className="inline-flex min-h-9 items-center justify-center rounded-lg bg-slate-100 px-3 text-xs font-semibold text-slate-700 transition hover:bg-slate-200"
                    href={`/dashboard/scheduler?date=${date}&task=${task.id}`}
                  >
                    Find time
                  </Link>
                  <details
                    className="relative"
                    onMouseEnter={(event) => {
                      const menu = event.currentTarget;
                      const timer = Number(menu.dataset.closeTimer ?? "");
                      if (timer) {
                        window.clearTimeout(timer);
                        delete menu.dataset.closeTimer;
                      }
                    }}
                    onMouseLeave={(event) => {
                      const menu = event.currentTarget;
                      const timer = Number(menu.dataset.closeTimer ?? "");
                      if (timer) window.clearTimeout(timer);
                      menu.dataset.closeTimer = String(
                        window.setTimeout(() => {
                          menu.open = false;
                          delete menu.dataset.closeTimer;
                        }, 350),
                      );
                    }}
                  >
                    <summary
                      aria-label={`More actions for ${task.title}`}
                      className="grid min-h-9 min-w-9 list-none place-items-center rounded-lg text-lg font-bold text-slate-500 transition hover:bg-slate-100 hover:text-slate-900 [&::-webkit-details-marker]:hidden"
                    >
                      ···
                    </summary>
                    <div className="absolute right-0 top-full z-20 pt-2">
                      <div className="min-w-32 overflow-hidden rounded-xl border border-slate-200 bg-white p-1 shadow-xl">
                        <button
                          className="block w-full rounded-lg px-3 py-2 text-left text-sm font-semibold text-slate-700 hover:bg-slate-50"
                          disabled={busy}
                          onClick={(event) => {
                            const menu = event.currentTarget.closest("details");
                            if (menu) menu.open = false;
                            if (
                              task.task_status === "success" ||
                              task.task_status === "failed"
                            ) {
                              setEditingLogged(task);
                            } else {
                              setEditing(task);
                            }
                          }}
                        >
                          Edit
                        </button>
                        <button
                          className="block w-full rounded-lg px-3 py-2 text-left text-sm font-semibold text-rose-700 hover:bg-rose-50"
                          disabled={busy}
                          onClick={(event) => {
                            const menu = event.currentTarget.closest("details");
                            if (menu) menu.open = false;
                            setRemoving(task);
                          }}
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  </details>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
      {editing && (
        <QuickAddForm
          initialDate={date}
          initialDraft={draft}
          excludeTaskId={editing !== "new" ? editing.id : undefined}
          onDismiss={() => setEditing(null)}
          onSubmit={save}
        />
      )}
      {editingLogged && (
        <LoggedPlanEditForm
          task={editingLogged}
          onDismiss={() => setEditingLogged(null)}
          onWarn={(title, message) => toast.warn(title, message)}
          onSaved={() => {
            setEditingLogged(null);
            toast.success("Logged plan updated");
            void load();
          }}
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
