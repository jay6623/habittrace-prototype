"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useAuth } from "@/app/providers";
import {
  ApiError,
  confirmDailySchedule,
  generateDailySchedule,
  updateDailySchedule,
  type DailySchedule,
  type DailyScheduleTaskDraft,
} from "@/lib/api";
import { localDateString, TASK_CATEGORIES } from "@/lib/mobile-task";
import { readPreferences } from "@/lib/preferences";
import { useToast } from "@/components/ui/toast";

type TaskEditor = DailyScheduleTaskDraft & {
  deadlineTime: string;
  fixedTime: string;
};

function newTask(): TaskEditor {
  return {
    clientId: crypto.randomUUID(),
    title: "",
    estimatedDurationMinutes: 30,
    importance: 3,
    category: "",
    difficulty: 3,
    requiredEnergy: 3,
    requiredFocus: 3,
    isFixedTime: false,
    deadlineTime: "",
    fixedTime: "",
  };
}

function localIso(date: string, time: string): string {
  return new Date(`${date}T${time}:00`).toISOString();
}

function localTime(value: string): string {
  const date = new Date(value);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function formatClock(value: string): string {
  return new Date(value).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

export default function DailyScheduleGeneratorPage() {
  const params = useSearchParams();
  const { user } = useAuth();
  const toast = useToast();
  const preferences = readPreferences(user?.user_metadata);
  const requestedDate = params.get("date");
  const [selectedDate, setSelectedDate] = useState(
    requestedDate && /^\d{4}-\d{2}-\d{2}$/.test(requestedDate)
      ? requestedDate
      : localDateString(),
  );
  const [tasks, setTasks] = useState<TaskEditor[]>([newTask()]);
  const [dayStart, setDayStart] = useState(preferences.workStart);
  const [dayEnd, setDayEnd] = useState(preferences.workEnd);
  const [buffer, setBuffer] = useState(15);
  const [schedule, setSchedule] = useState<DailySchedule | null>(null);
  const [busy, setBusy] = useState(false);
  const [savingTaskId, setSavingTaskId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  function updateTask<K extends keyof TaskEditor>(
    id: string,
    key: K,
    value: TaskEditor[K],
  ) {
    setTasks((current) =>
      current.map((task) => (task.clientId === id ? { ...task, [key]: value } : task)),
    );
  }

  async function generate(event: FormEvent) {
    event.preventDefault();
    setError(null);
    const clean = tasks.filter((task) => task.title.trim());
    if (!clean.length) {
      setError("Add at least one task with a title.");
      return;
    }
    const missingCategory = clean.find((task) => !task.category);
    if (missingCategory) {
      setError(`Choose a category for ${missingCategory.title}.`);
      return;
    }
    const invalidFixed = clean.find((task) => task.isFixedTime && !task.fixedTime);
    if (invalidFixed) {
      setError(`Choose a fixed time for ${invalidFixed.title}.`);
      return;
    }
    if (dayEnd <= dayStart) {
      setError("Your day must end after it starts.");
      return;
    }
    setBusy(true);
    try {
      const result = await generateDailySchedule({
        selectedDate,
        timezoneName: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
        dayStart,
        dayEnd,
        minimumBufferMinutes: buffer,
        tasks: clean.map((task) => ({
          ...task,
          title: task.title.trim(),
          deadlineAt: task.deadlineTime
            ? localIso(selectedDate, task.deadlineTime)
            : null,
          fixedStart:
            task.isFixedTime && task.fixedTime
              ? localIso(selectedDate, task.fixedTime)
              : null,
        })),
      });
      setSchedule(result);
      toast.success("Draft schedule generated", "Review and adjust it before confirming.");
    } catch (cause) {
      setError(
        cause instanceof ApiError && cause.detail
          ? cause.detail
          : "We couldn’t generate a schedule. Check the backend connection and try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function moveTask(taskId: string, time: string) {
    if (!schedule || !time) return;
    setSavingTaskId(taskId);
    setError(null);
    try {
      const updated = await updateDailySchedule(schedule.id, [
        { taskId, scheduledStart: localIso(schedule.selected_date, time) },
      ]);
      setSchedule(updated);
      toast.success("Draft time updated");
    } catch (cause) {
      setError(
        cause instanceof ApiError && cause.detail
          ? cause.detail
          : "That time could not be saved. It may overlap another plan or buffer.",
      );
    } finally {
      setSavingTaskId(null);
    }
  }

  async function confirm() {
    if (!schedule || schedule.status !== "draft") return;
    setBusy(true);
    setError(null);
    try {
      const confirmed = await confirmDailySchedule(schedule.id);
      setSchedule(confirmed);
      toast.success("Daily plan confirmed", "The scheduled tasks are now in HabitTrace.");
    } catch (cause) {
      setError(
        cause instanceof ApiError && cause.detail
          ? cause.detail
          : "The draft could not be confirmed. No draft changes were lost.",
      );
    } finally {
      setBusy(false);
    }
  }

  if (schedule) {
    return (
      <div className="space-y-6">
        <header className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-3xl font-bold">Your generated day</h1>
              <span
                className={`rounded-full px-3 py-1 text-xs font-bold uppercase tracking-wide ${
                  schedule.status === "draft"
                    ? "bg-amber-100 text-amber-800"
                    : "bg-emerald-100 text-emerald-800"
                }`}
              >
                {schedule.status}
              </span>
            </div>
            <p className="mt-2 text-sm text-slate-500">
              {new Date(`${schedule.selected_date}T12:00:00`).toLocaleDateString([], {
                weekday: "long",
                month: "long",
                day: "numeric",
              })} · {schedule.minimum_buffer_minutes}-minute buffers
            </p>
          </div>
          <button
            className="btn-secondary"
            type="button"
            onClick={() => {
              setSchedule(null);
              setError(null);
            }}
          >
            Start a new draft
          </button>
        </header>

        {error && <p role="alert" className="rounded-2xl bg-rose-50 p-4 text-sm text-rose-800">{error}</p>}
        {schedule.warnings.map((warning) => (
          <p key={warning} className="rounded-2xl bg-amber-50 p-4 text-sm text-amber-900">{warning}</p>
        ))}

        <div className="grid gap-6 lg:grid-cols-[minmax(0,1.5fr)_minmax(18rem,.75fr)]">
          <section className="panel">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-xs font-bold uppercase tracking-[.16em] text-slate-400">Timeline</p>
                <h2 className="mt-1 text-xl font-bold">Optimized schedule</h2>
              </div>
              <p className="text-sm text-slate-500">Times are estimated, not guaranteed.</p>
            </div>
            {schedule.scheduled_tasks.length ? (
              <ol className="relative mt-6 space-y-4 before:absolute before:bottom-6 before:left-[4.3rem] before:top-6 before:w-px before:bg-slate-200">
                {schedule.scheduled_tasks.map((task) => (
                  <li key={task.task_id} className="relative grid grid-cols-[3.7rem_1fr] gap-5">
                    <time className="pt-4 text-right text-sm font-bold text-slate-700">
                      {formatClock(task.scheduled_start)}
                    </time>
                    <article className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <h3 className="font-bold">{task.title}</h3>
                          <p className="mt-1 text-sm text-slate-500">
                            {task.estimated_duration_minutes} min · {task.category} · importance {task.importance}/5
                          </p>
                        </div>
                        <span className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700">
                          {Math.round(task.predicted_success_probability * 100)}% estimated
                        </span>
                      </div>
                      <p className="mt-3 text-sm leading-relaxed text-slate-600">{task.explanation}</p>
                      {schedule.status === "draft" && !task.is_fixed_time && (
                        <label className="mt-4 flex max-w-xs items-center gap-3 text-sm font-semibold">
                          Adjust time
                          <input
                            aria-label={`Adjust ${task.title} time`}
                            className="field !w-auto"
                            type="time"
                            step={schedule.slot_interval_minutes * 60}
                            defaultValue={localTime(task.scheduled_start)}
                            disabled={savingTaskId === task.task_id}
                            onChange={(event) => void moveTask(task.task_id, event.target.value)}
                          />
                        </label>
                      )}
                      {task.is_fixed_time && (
                        <p className="mt-3 text-xs font-bold uppercase tracking-wide text-slate-500">Fixed-time event</p>
                      )}
                    </article>
                  </li>
                ))}
              </ol>
            ) : (
              <p className="mt-6 text-slate-500">No tasks could be placed in this day.</p>
            )}
          </section>

          <aside className="space-y-5">
            {schedule.unscheduled_tasks.length > 0 && (
              <section className="rounded-3xl border border-amber-200 bg-amber-50 p-5">
                <h2 className="font-bold text-amber-950">Couldn&apos;t schedule</h2>
                <ul className="mt-4 space-y-4">
                  {schedule.unscheduled_tasks.map((task) => (
                    <li key={task.task_id} className="text-sm text-amber-950">
                      <p className="font-semibold">{task.title}</p>
                      <p className="mt-1 text-amber-800">{task.reason}</p>
                    </li>
                  ))}
                </ul>
              </section>
            )}
            <section className="panel">
              {schedule.status === "draft" ? (
                <>
                  <h2 className="font-bold">Ready to use this plan?</h2>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">
                    Confirming creates only the scheduled tasks. Unscheduled tasks stay in this draft.
                  </p>
                  <button
                    className="btn-primary mt-5 w-full"
                    disabled={busy || !schedule.scheduled_tasks.length}
                    onClick={() => void confirm()}
                  >
                    {busy ? "Confirming…" : "Confirm daily plan"}
                  </button>
                </>
              ) : (
                <>
                  <h2 className="font-bold text-emerald-800">Plan confirmed</h2>
                  <p className="mt-2 text-sm text-slate-600">Your tasks are now part of the active schedule.</p>
                  <Link className="btn-primary mt-5 block text-center" href={`/dashboard/calendar?date=${schedule.selected_date}`}>
                    View calendar
                  </Link>
                </>
              )}
            </section>
          </aside>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header>
        <p className="text-xs font-bold uppercase tracking-[.18em] text-emerald-700">Daily Schedule Generator</p>
        <h1 className="mt-2 text-3xl font-bold">Generate today&apos;s plan</h1>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-slate-600">
          Add what you need to do without choosing times. HabitTrace will build a realistic draft around your existing plans and calendar.
        </p>
      </header>

      {error && <p role="alert" className="rounded-2xl bg-rose-50 p-4 text-sm text-rose-800">{error}</p>}

      <form className="space-y-6" onSubmit={generate}>
        <section className="panel grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <label className="text-sm font-semibold">
            Day
            <input className="field mt-2" type="date" required value={selectedDate} onChange={(event) => setSelectedDate(event.target.value)} />
          </label>
          <label className="text-sm font-semibold">
            Start of day
            <input className="field mt-2" type="time" required value={dayStart} onChange={(event) => setDayStart(event.target.value)} />
          </label>
          <label className="text-sm font-semibold">
            End of day
            <input className="field mt-2" type="time" required value={dayEnd} onChange={(event) => setDayEnd(event.target.value)} />
          </label>
          <label className="text-sm font-semibold">
            Buffer
            <select className="field mt-2" value={buffer} onChange={(event) => setBuffer(Number(event.target.value))}>
              {[0, 5, 10, 15, 20, 30].map((minutes) => <option key={minutes} value={minutes}>{minutes} minutes</option>)}
            </select>
          </label>
        </section>

        <section className="space-y-4">
          <div className="flex items-center justify-between gap-4">
            <div>
              <h2 className="text-xl font-bold">Tasks to place</h2>
              <p className="mt-1 text-sm text-slate-500">Title, category, duration, and importance help the AI choose a better time.</p>
            </div>
            <button type="button" className="btn-secondary" onClick={() => setTasks((current) => [...current, newTask()])}>+ Add task</button>
          </div>

          {tasks.map((task, index) => (
            <article key={task.clientId} className="panel space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="font-bold">Task {index + 1}</h3>
                {tasks.length > 1 && (
                  <button type="button" className="text-sm font-semibold text-rose-700" onClick={() => setTasks((current) => current.filter((item) => item.clientId !== task.clientId))}>Remove</button>
                )}
              </div>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[minmax(0,2fr)_1fr_1fr_1fr]">
                <label className="text-sm font-semibold">
                  Title
                  <input className="field mt-2" required maxLength={200} placeholder="e.g. Finish project outline" value={task.title} onChange={(event) => updateTask(task.clientId, "title", event.target.value)} />
                </label>
                <label className="text-sm font-semibold">
                  Category
                  <select className="field mt-2" required value={task.category} onChange={(event) => updateTask(task.clientId, "category", event.target.value)}>
                    <option value="" disabled>Choose category</option>
                    {TASK_CATEGORIES.map((category) => <option key={category} value={category}>{category}</option>)}
                  </select>
                </label>
                <label className="text-sm font-semibold">
                  Duration
                  <select className="field mt-2" value={task.estimatedDurationMinutes} onChange={(event) => updateTask(task.clientId, "estimatedDurationMinutes", Number(event.target.value))}>
                    {[15, 30, 45, 60, 90, 120, 180].map((minutes) => <option key={minutes} value={minutes}>{minutes} min</option>)}
                  </select>
                </label>
                <label className="text-sm font-semibold">
                  Importance
                  <select className="field mt-2" value={task.importance} onChange={(event) => updateTask(task.clientId, "importance", Number(event.target.value))}>
                    {[1, 2, 3, 4, 5].map((value) => <option key={value} value={value}>{value}/5</option>)}
                  </select>
                </label>
              </div>

              <details className="rounded-2xl bg-slate-50 p-4">
                <summary className="cursor-pointer text-sm font-semibold text-slate-700">Optional scheduling details</summary>
                <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  <label className="text-sm font-semibold">
                    Difficulty
                    <select className="field mt-2" value={task.difficulty} onChange={(event) => updateTask(task.clientId, "difficulty", Number(event.target.value))}>
                      {[1, 2, 3, 4, 5].map((value) => <option key={value} value={value}>{value}/5</option>)}
                    </select>
                  </label>
                  <label className="text-sm font-semibold">
                    Energy needed
                    <select className="field mt-2" value={task.requiredEnergy} onChange={(event) => updateTask(task.clientId, "requiredEnergy", Number(event.target.value))}>
                      {[1, 2, 3, 4, 5].map((value) => <option key={value} value={value}>{value}/5</option>)}
                    </select>
                  </label>
                  <label className="text-sm font-semibold">
                    Focus needed
                    <select className="field mt-2" value={task.requiredFocus} onChange={(event) => updateTask(task.clientId, "requiredFocus", Number(event.target.value))}>
                      {[1, 2, 3, 4, 5].map((value) => <option key={value} value={value}>{value}/5</option>)}
                    </select>
                  </label>
                  <label className="text-sm font-semibold">
                    Deadline on this day
                    <input className="field mt-2" type="time" value={task.deadlineTime} onChange={(event) => updateTask(task.clientId, "deadlineTime", event.target.value)} />
                  </label>
                  <label className="flex items-center gap-3 self-end rounded-xl border border-slate-200 bg-white px-3 py-3 text-sm font-semibold">
                    <input type="checkbox" checked={task.isFixedTime} onChange={(event) => updateTask(task.clientId, "isFixedTime", event.target.checked)} />
                    Fixed-time event
                  </label>
                  {task.isFixedTime && (
                    <label className="text-sm font-semibold">
                      Fixed start
                      <input className="field mt-2" type="time" required value={task.fixedTime} onChange={(event) => updateTask(task.clientId, "fixedTime", event.target.value)} />
                    </label>
                  )}
                </div>
              </details>
            </article>
          ))}
        </section>

        <div className="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <Link className="btn-secondary text-center" href="/dashboard/scheduler">Cancel</Link>
          <button className="btn-primary" disabled={busy} type="submit">{busy ? "Building your day…" : "Generate draft schedule"}</button>
        </div>
      </form>
    </div>
  );
}
