"use client";

import { useCallback, useEffect, useState } from "react";
import QuickAddForm from "@/components/mobile/quick-add-form";
import Dialog from "@/components/ui/dialog";
import { toQuickTaskCreate } from "@/lib/mobile-task";
import { useDataRefresh } from "@/lib/refresh";
import { createTask, getTasks, type Task } from "@/lib/api";

const categoryChipColors: Record<string, string> = {
  Study: "bg-sky-100 text-sky-800",
  Work: "bg-violet-100 text-violet-800",
  Chores: "bg-amber-100 text-amber-800",
  "Fitness/Health": "bg-emerald-100 text-emerald-800",
  "Errands/Admin": "bg-slate-100 text-slate-700",
  "Hobbies/Leisure": "bg-rose-100 text-rose-800",
  Social: "bg-indigo-100 text-indigo-800",
  Other: "bg-gray-100 text-gray-700",
};

const DAYS_OF_WEEK = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTH_NAMES = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

function localDateStr(date = new Date()): string {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function dateFromParts(year: number, month: number, day: number): string {
  return localDateStr(new Date(year, month, day, 12));
}

function dateFromIso(iso: string): Date {
  return new Date(`${iso}T12:00:00`);
}

function getDaysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate();
}

function getFirstDayOfMonth(year: number, month: number) {
  return new Date(year, month, 1).getDay();
}

function formatDateLabel(iso: string): string {
  return dateFromIso(iso).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function timeToMinutes(timeStr: string): number {
  const match = timeStr.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!match) return 0;
  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const meridiem = match[3].toUpperCase();
  if (meridiem === "AM" && hour === 12) hour = 0;
  if (meridiem === "PM" && hour !== 12) hour += 12;
  return hour * 60 + minute;
}

function statusLabel(task: Task) {
  if (task.task_status === "success") return "Completed";
  if (task.task_status === "failed") return "Not completed";
  return "Planned";
}

export default function CalendarPage() {
  const today = new Date();
  const todayIso = localDateStr(today);
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [weekAnchor, setWeekAnchor] = useState(todayIso);
  const [view, setView] = useState<"month" | "week">("month");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  const [error, setError] = useState<string | null>(null);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [selectedTask, setSelectedTask] = useState<Task | null>(null);
  const [draft, setDraft] = useState<{ planned_date: string } | null>(null);

  const loadTasks = useCallback(() => {
    setLoading(true);
    setError(null);
    getTasks()
      .then((items) => setTasks(items))
      .catch((err) => {
        console.warn("Could not load tasks:", err);
        setTasks([]);
        setError("Couldn’t load your calendar. Please try again.");
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    const timer = setTimeout(loadTasks, 0);
    return () => clearTimeout(timer);
  }, [loadTasks]);

  useDataRefresh(loadTasks);

  const daysInMonth = getDaysInMonth(year, month);
  const firstDay = getFirstDayOfMonth(year, month);
  const prevMonthDays = getDaysInMonth(year, month - 1);
  const trailingDays = Array.from(
    { length: firstDay },
    (_, i) => prevMonthDays - firstDay + 1 + i,
  );
  const currentDays = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  const totalCells = trailingDays.length + currentDays.length;
  const remainingCells = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  const leadingDays = Array.from({ length: remainingCells }, (_, i) => i + 1);

  function openDay(date: string) {
    setError(null);
    setSelectedTask(null);
    setSelectedDate(date);
  }

  function openAddTask(date: string) {
    setError(null);
    setSelectedTask(null);
    setSelectedDate(null);
    setDraft({ planned_date: date });
  }

  function goToPrevMonth() {
    if (month === 0) {
      setMonth(11);
      setYear((value) => value - 1);
    } else {
      setMonth((value) => value - 1);
    }
  }

  function goToNextMonth() {
    if (month === 11) {
      setMonth(0);
      setYear((value) => value + 1);
    } else {
      setMonth((value) => value + 1);
    }
  }

  function goToToday() {
    setYear(today.getFullYear());
    setMonth(today.getMonth());
    setWeekAnchor(todayIso);
  }

  function moveWeek(offset: number) {
    const next = dateFromIso(weekAnchor);
    next.setDate(next.getDate() + offset * 7);
    setWeekAnchor(localDateStr(next));
  }

  function changeView(nextView: "month" | "week") {
    if (nextView === view) return;
    if (nextView === "week") {
      const day = Math.min(today.getDate(), getDaysInMonth(year, month));
      setWeekAnchor(dateFromParts(year, month, day));
    } else {
      const anchor = dateFromIso(weekAnchor);
      setYear(anchor.getFullYear());
      setMonth(anchor.getMonth());
    }
    setView(nextView);
  }

  function tasksForDate(date: string): Task[] {
    return tasks
      .filter((task) => task.planned_date === date)
      .sort(
        (a, b) =>
          timeToMinutes(a.planned_start_time) -
          timeToMinutes(b.planned_start_time),
      );
  }

  function taskChipColor(task: Task) {
    if (task.task_status === "success")
      return "bg-emerald-100 text-emerald-800";
    if (task.task_status === "failed") return "bg-rose-100 text-rose-800";
    return (
      categoryChipColors[task.task_category] ?? "bg-slate-100 text-slate-700"
    );
  }

  function weekDays() {
    const anchor = dateFromIso(weekAnchor);
    const sunday = new Date(anchor);
    sunday.setDate(anchor.getDate() - anchor.getDay());
    return Array.from({ length: 7 }, (_, index) => {
      const date = new Date(sunday);
      date.setDate(sunday.getDate() + index);
      return date;
    });
  }

  const visibleWeek = weekDays();
  const weekStart = visibleWeek[0];
  const weekEnd = visibleWeek[6];
  const weekLabel =
    weekStart.getFullYear() === weekEnd.getFullYear()
      ? `${weekStart.toLocaleDateString("en-US", { month: "short", day: "numeric" })} – ${weekEnd.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}`
      : `${weekStart.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })} – ${weekEnd.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}`;

  const dayPlans = selectedDate ? tasksForDate(selectedDate) : [];

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <div className="text-sm text-slate-500">Calendar</div>
          <h1 className="text-2xl font-bold">Task Calendar</h1>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => (view === "month" ? goToPrevMonth() : moveWeek(-1))}
              className="grid h-9 w-9 place-items-center rounded-xl border border-slate-200 bg-white hover:bg-slate-50"
              aria-label={view === "month" ? "Previous month" : "Previous week"}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path
                  d="M15 18l-6-6 6-6"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </button>
            <span className="min-w-[140px] text-center text-sm font-semibold">
              {view === "month" ? `${MONTH_NAMES[month]} ${year}` : weekLabel}
            </span>
            <button
              type="button"
              onClick={() => (view === "month" ? goToNextMonth() : moveWeek(1))}
              className="grid h-9 w-9 place-items-center rounded-xl border border-slate-200 bg-white hover:bg-slate-50"
              aria-label={view === "month" ? "Next month" : "Next week"}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path
                  d="M9 18l6-6-6-6"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
            </button>
          </div>

          <button
            type="button"
            onClick={goToToday}
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            Today
          </button>

          <button
            type="button"
            onClick={() => openAddTask(todayIso)}
            className="rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-800"
          >
            + Add task
          </button>

          <div className="flex overflow-hidden rounded-xl border border-slate-200">
            {(["month", "week"] as const).map((nextView) => (
              <button
                key={nextView}
                type="button"
                onClick={() => changeView(nextView)}
                className={`px-4 py-2 text-sm font-medium capitalize transition-colors ${
                  view === nextView
                    ? "bg-white text-slate-900"
                    : "bg-slate-50 text-slate-500 hover:text-slate-700"
                }`}
              >
                {nextView}
              </button>
            ))}
          </div>
        </div>
      </div>

      {error && (
        <div role="alert" className="panel">
          {error}{" "}
          <button className="btn-secondary" onClick={loadTasks}>
            Retry
          </button>
        </div>
      )}
      {loading && (
        <div className="py-4 text-center text-sm text-slate-400 animate-pulse">
          Loading tasks...
        </div>
      )}

      {view === "month" && (
        <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white p-5">
          <div className="mb-3 grid min-w-[560px] grid-cols-7 gap-3">
            {DAYS_OF_WEEK.map((day) => (
              <div
                key={day}
                className="text-center text-sm font-medium text-slate-500"
              >
                {day}
              </div>
            ))}
          </div>

          <div className="grid min-w-[560px] grid-cols-7 gap-3">
            {trailingDays.map((day) => (
              <div
                key={`prev-${day}`}
                className="flex min-h-[104px] items-start rounded-2xl border border-slate-100 bg-slate-50/50 p-2"
              >
                <span className="text-sm text-slate-300">{day}</span>
              </div>
            ))}

            {currentDays.map((day) => {
              const date = dateFromParts(year, month, day);
              const dayTasks = tasksForDate(date);
              const isToday = date === todayIso;

              return (
                <button
                  key={`curr-${day}`}
                  type="button"
                  onClick={() => openDay(date)}
                  className={`flex min-h-[104px] flex-col items-start justify-start rounded-2xl border p-2 text-left transition-colors hover:border-slate-400 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-300 ${
                    isToday
                      ? "border-slate-900 bg-slate-50"
                      : "border-slate-200 bg-white"
                  }`}
                  aria-label={`View plans on ${formatDateLabel(date)}`}
                >
                  <span
                    className={`text-sm font-medium ${
                      isToday
                        ? "inline-flex h-6 w-6 items-center justify-center rounded-full bg-slate-900 text-white"
                        : "text-slate-700"
                    }`}
                  >
                    {day}
                  </span>

                  {dayTasks.slice(0, 3).map((task) => (
                    <div
                      key={task.id}
                      className={`mt-1.5 w-full truncate rounded-lg px-2 py-1 text-xs font-medium ${taskChipColor(task)}`}
                      title={task.title}
                    >
                      {task.planned_start_time && (
                        <span className="mr-1 opacity-60">
                          {task.planned_start_time}
                        </span>
                      )}
                      {task.title}
                    </div>
                  ))}
                  {dayTasks.length > 3 && (
                    <div className="mt-1 pl-2 text-xs text-slate-400">
                      +{dayTasks.length - 3} more
                    </div>
                  )}
                </button>
              );
            })}

            {leadingDays.map((day) => (
              <div
                key={`next-${day}`}
                className="flex min-h-[104px] items-start rounded-2xl border border-slate-100 bg-slate-50/50 p-2"
              >
                <span className="text-sm text-slate-300">{day}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {view === "week" && (
        <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white p-5">
          <div className="grid gap-3 md:grid-cols-7">
            {visibleWeek.map((dateObject) => {
              const date = localDateStr(dateObject);
              const dayTasks = tasksForDate(date);
              const isToday = date === todayIso;

              return (
                <button
                  key={date}
                  type="button"
                  onClick={() => openDay(date)}
                  className="flex min-h-[160px] flex-col gap-2 rounded-2xl border border-slate-100 p-2 text-left transition-colors hover:border-slate-300 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-300"
                  aria-label={`View plans on ${formatDateLabel(date)}`}
                >
                  <div className="text-center">
                    <div className="text-xs text-slate-500">
                      {DAYS_OF_WEEK[dateObject.getDay()]}
                    </div>
                    <div
                      className={`mx-auto mt-1 flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold ${
                        isToday ? "bg-slate-900 text-white" : "text-slate-700"
                      }`}
                    >
                      {dateObject.getDate()}
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    {dayTasks.map((task) => (
                      <div
                        key={task.id}
                        className={`rounded-lg px-2 py-1.5 text-xs font-medium ${taskChipColor(task)}`}
                      >
                        <div className="truncate">{task.title}</div>
                        {task.planned_start_time && (
                          <div className="mt-0.5 opacity-60">
                            {task.planned_start_time} -{" "}
                            {task.planned_duration_min}m
                          </div>
                        )}
                      </div>
                    ))}
                    {dayTasks.length === 0 && (
                      <div className="pt-4 text-center text-xs text-slate-300">
                        -
                      </div>
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}

      <div className="flex flex-wrap gap-3 text-xs text-slate-500">
        <div className="flex items-center gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-emerald-400" />
          Success
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-rose-400" />
          Failed
        </div>
        <div className="flex items-center gap-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-sky-400" />
          Pending
        </div>
      </div>

      {selectedDate && !selectedTask && (
        <Dialog
          title={formatDateLabel(selectedDate)}
          onClose={() => setSelectedDate(null)}
        >
          <div className="space-y-4">
            {dayPlans.length === 0 ? (
              <p className="rounded-2xl border border-dashed border-slate-200 bg-slate-50 px-4 py-8 text-center text-sm text-slate-500">
                No plans on this day yet.
              </p>
            ) : (
              <ul className="space-y-2">
                {dayPlans.map((task) => (
                  <li key={task.id}>
                    <button
                      type="button"
                      className="flex w-full items-start justify-between gap-3 rounded-2xl border border-slate-200 bg-white px-4 py-3 text-left transition hover:border-slate-300 hover:bg-slate-50"
                      onClick={() => setSelectedTask(task)}
                    >
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-slate-950">
                          {task.title}
                        </p>
                        <p className="mt-1 text-xs font-medium text-slate-500">
                          {task.planned_start_time} · {task.planned_duration_min}{" "}
                          min · {task.task_category}
                        </p>
                      </div>
                      <span
                        className={`shrink-0 rounded-full px-2.5 py-1 text-[11px] font-semibold ${taskChipColor(task)}`}
                      >
                        {statusLabel(task)}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <button
              type="button"
              className="btn-primary w-full"
              onClick={() => {
                const date = selectedDate;
                setSelectedDate(null);
                openAddTask(date);
              }}
            >
              + Add plan
            </button>
          </div>
        </Dialog>
      )}

      {selectedTask && (
        <Dialog
          title="Plan details"
          onClose={() => setSelectedTask(null)}
        >
          <div className="space-y-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                Name
              </p>
              <p className="mt-1 text-lg font-bold text-slate-950">
                {selectedTask.title}
              </p>
            </div>
            {selectedTask.notes?.trim() && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Note
                </p>
                <p className="mt-1 whitespace-pre-wrap text-sm leading-relaxed text-slate-700">
                  {selectedTask.notes.trim()}
                </p>
              </div>
            )}
            <dl className="grid grid-cols-2 gap-3 rounded-2xl bg-slate-50 p-4 text-sm">
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Category
                </dt>
                <dd className="mt-1 font-semibold text-slate-900">
                  {selectedTask.task_category}
                </dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Priority
                </dt>
                <dd className="mt-1 font-semibold text-slate-900">
                  {selectedTask.importance}
                  {selectedTask.importance === 1
                    ? " — Low"
                    : selectedTask.importance === 5
                      ? " — High"
                      : ""}
                </dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Date
                </dt>
                <dd className="mt-1 font-semibold text-slate-900">
                  {formatDateLabel(selectedTask.planned_date)}
                </dd>
              </div>
              <div>
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Time
                </dt>
                <dd className="mt-1 font-semibold text-slate-900">
                  {selectedTask.planned_start_time} ·{" "}
                  {selectedTask.planned_duration_min} min
                </dd>
              </div>
              <div className="col-span-2">
                <dt className="text-xs font-semibold uppercase tracking-wide text-slate-400">
                  Status
                </dt>
                <dd className="mt-1">
                  <span
                    className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${taskChipColor(selectedTask)}`}
                  >
                    {statusLabel(selectedTask)}
                  </span>
                </dd>
              </div>
            </dl>
            <button
              type="button"
              className="btn-secondary w-full"
              onClick={() => setSelectedTask(null)}
            >
              Back to day
            </button>
          </div>
        </Dialog>
      )}

      {draft && (
        <QuickAddForm
          initialDate={draft.planned_date}
          onDismiss={() => setDraft(null)}
          onSubmit={async (value) => {
            await createTask(
              toQuickTaskCreate(
                value,
                tasksForDate(value.plannedDate).length + 1,
              ),
            );
            setDraft(null);
            loadTasks();
          }}
        />
      )}
    </div>
  );
}
