"use client";

import { useCallback, useEffect, useState } from "react";
import { createTask, getTasks, type Task, type TaskCreate } from "@/lib/api";

const CATEGORIES = [
  "Study",
  "Work",
  "Chores",
  "Fitness/Health",
  "Errands/Admin",
  "Hobbies/Leisure",
  "Social",
  "Other",
];

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
const HOURS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"];
const MINUTES = ["00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"];

type DraftTask = {
  title: string;
  task_category: string;
  planned_date: string;
  hour: string;
  minute: string;
  meridiem: "AM" | "PM";
  planned_duration_min: string;
  importance: number;
  energy_level: number;
  focus_level: number;
};

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

function nowTimeParts(): Pick<DraftTask, "hour" | "minute" | "meridiem"> {
  const now = new Date();
  let hour = now.getHours();
  let meridiem: "AM" | "PM" = hour < 12 ? "AM" : "PM";
  if (hour === 0) hour = 12;
  if (hour > 12) hour -= 12;
  const roundedMinute = Math.ceil(now.getMinutes() / 5) * 5;
  if (roundedMinute === 60) {
    if (hour === 11) meridiem = meridiem === "AM" ? "PM" : "AM";
    hour = (hour % 12) + 1;
  }
  return {
    hour: String(hour),
    minute: String(roundedMinute % 60).padStart(2, "0"),
    meridiem,
  };
}

function newDraft(date: string): DraftTask {
  const time =
    date === localDateStr()
      ? nowTimeParts()
      : { hour: "9", minute: "00", meridiem: "AM" as const };
  return {
    title: "",
    task_category: "Study",
    planned_date: date,
    hour: time.hour,
    minute: time.minute,
    meridiem: time.meridiem,
    planned_duration_min: "60",
    importance: 3,
    energy_level: 3,
    focus_level: 3,
  };
}

function taskTime(draft: DraftTask): string {
  return `${draft.hour}:${draft.minute} ${draft.meridiem}`;
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

function RatingDots({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
}) {
  return (
    <div>
      <div className="mb-1.5 text-xs font-medium text-slate-500">{label}</div>
      <div className="flex gap-1.5">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            onClick={() => onChange(n)}
            className={`h-8 w-8 rounded-lg text-xs font-semibold transition-colors ${
              n <= value
                ? "bg-slate-900 text-white"
                : "bg-slate-100 text-slate-400 hover:bg-slate-200"
            }`}
          >
            {n}
          </button>
        ))}
      </div>
    </div>
  );
}

function TimePicker({
  draft,
  setDraft,
}: {
  draft: DraftTask;
  setDraft: (draft: DraftTask) => void;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-medium text-slate-500">Start time</label>
      <div className="flex items-center gap-1">
        <select
          value={draft.hour}
          onChange={(event) => setDraft({ ...draft, hour: event.target.value })}
          className="min-w-0 flex-1 cursor-pointer rounded-xl bg-slate-100 px-2 py-2.5 text-sm outline-none"
        >
          {HOURS.map((hour) => (
            <option key={hour} value={hour}>
              {hour}
            </option>
          ))}
        </select>
        <span className="text-sm font-semibold text-slate-400">:</span>
        <select
          value={draft.minute}
          onChange={(event) => setDraft({ ...draft, minute: event.target.value })}
          className="min-w-0 flex-1 cursor-pointer rounded-xl bg-slate-100 px-2 py-2.5 text-sm outline-none"
        >
          {MINUTES.map((minute) => (
            <option key={minute} value={minute}>
              {minute}
            </option>
          ))}
        </select>
        <div className="flex shrink-0 overflow-hidden rounded-xl border border-slate-200">
          {(["AM", "PM"] as const).map((meridiem) => (
            <button
              key={meridiem}
              type="button"
              onClick={() => setDraft({ ...draft, meridiem })}
              className={`px-2.5 py-2.5 text-xs font-semibold transition-colors ${
                draft.meridiem === meridiem
                  ? "bg-slate-900 text-white"
                  : "bg-white text-slate-500 hover:bg-slate-50"
              }`}
            >
              {meridiem}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

export default function CalendarPage() {
  const today = new Date();
  const todayIso = localDateStr(today);
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [view, setView] = useState<"month" | "week">("month");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState<DraftTask | null>(null);

  const loadTasks = useCallback(() => {
    setLoading(true);
    getTasks()
      .then((items) => setTasks(items))
      .catch((err) => {
        console.warn("Could not load tasks:", err);
        setTasks([]);
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    loadTasks();
  }, [loadTasks]);

  const daysInMonth = getDaysInMonth(year, month);
  const firstDay = getFirstDayOfMonth(year, month);
  const prevMonthDays = getDaysInMonth(year, month - 1);
  const trailingDays = Array.from({ length: firstDay }, (_, i) => prevMonthDays - firstDay + 1 + i);
  const currentDays = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  const totalCells = trailingDays.length + currentDays.length;
  const remainingCells = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  const leadingDays = Array.from({ length: remainingCells }, (_, i) => i + 1);

  function openAddTask(date: string) {
    setError(null);
    setDraft(newDraft(date));
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
    if (view === "week") openAddTask(todayIso);
  }

  function tasksForDate(date: string): Task[] {
    return tasks
      .filter((task) => task.planned_date === date)
      .sort((a, b) => timeToMinutes(a.planned_start_time) - timeToMinutes(b.planned_start_time));
  }

  function taskChipColor(task: Task) {
    if (task.task_status === "success") return "bg-emerald-100 text-emerald-800";
    if (task.task_status === "failed") return "bg-rose-100 text-rose-800";
    return categoryChipColors[task.task_category] ?? "bg-slate-100 text-slate-700";
  }

  function weekDays() {
    const anchor = draft ? dateFromIso(draft.planned_date) : new Date(year, month, today.getDate(), 12);
    const sunday = new Date(anchor);
    sunday.setDate(anchor.getDate() - anchor.getDay());
    return Array.from({ length: 7 }, (_, index) => {
      const date = new Date(sunday);
      date.setDate(sunday.getDate() + index);
      return date;
    });
  }

  async function handleCreateTask() {
    if (!draft || saving) return;
    const title = draft.title.trim();
    if (!title) {
      setError("Task name is required.");
      return;
    }

    setSaving(true);
    setError(null);
    const task: TaskCreate = {
      title,
      task_category: draft.task_category,
      planned_start_time: taskTime(draft),
      planned_date: draft.planned_date,
      planned_duration_min: Number(draft.planned_duration_min),
      importance: draft.importance,
      energy_level: draft.energy_level,
      focus_level: draft.focus_level,
      total_tasks_today: tasksForDate(draft.planned_date).length + 1,
    };

    try {
      const created = await createTask(task);
      setTasks((prev) => [...prev, created]);
      const createdDate = dateFromIso(created.planned_date);
      setYear(createdDate.getFullYear());
      setMonth(createdDate.getMonth());
      setDraft(null);
    } catch (err) {
      console.warn("Calendar task creation failed:", err);
      setError(err instanceof Error ? err.message : "Could not add task.");
    } finally {
      setSaving(false);
    }
  }

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
              onClick={goToPrevMonth}
              className="grid h-9 w-9 place-items-center rounded-xl border border-slate-200 bg-white hover:bg-slate-50"
              aria-label="Previous month"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
            <span className="min-w-[140px] text-center text-sm font-semibold">
              {MONTH_NAMES[month]} {year}
            </span>
            <button
              type="button"
              onClick={goToNextMonth}
              className="grid h-9 w-9 place-items-center rounded-xl border border-slate-200 bg-white hover:bg-slate-50"
              aria-label="Next month"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path d="M9 18l6-6-6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
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
                onClick={() => setView(nextView)}
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

      {loading && (
        <div className="py-4 text-center text-sm text-slate-400 animate-pulse">
          Loading tasks...
        </div>
      )}

      {view === "month" && (
        <div className="rounded-2xl border border-slate-200 bg-white p-5">
          <div className="mb-3 grid grid-cols-7 gap-3">
            {DAYS_OF_WEEK.map((day) => (
              <div key={day} className="text-center text-sm font-medium text-slate-500">
                {day}
              </div>
            ))}
          </div>

          <div className="grid grid-cols-7 gap-3">
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
                  onClick={() => openAddTask(date)}
                  className={`flex min-h-[104px] flex-col items-start justify-start rounded-2xl border p-2 text-left transition-colors hover:border-slate-400 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-300 ${
                    isToday ? "border-slate-900 bg-slate-50" : "border-slate-200 bg-white"
                  }`}
                  aria-label={`Add task on ${formatDateLabel(date)}`}
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
                        <span className="mr-1 opacity-60">{task.planned_start_time}</span>
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
        <div className="rounded-2xl border border-slate-200 bg-white p-5">
          <div className="grid gap-3 md:grid-cols-7">
            {weekDays().map((dateObject) => {
              const date = localDateStr(dateObject);
              const dayTasks = tasksForDate(date);
              const isToday = date === todayIso;

              return (
                <button
                  key={date}
                  type="button"
                  onClick={() => openAddTask(date)}
                  className="flex min-h-[160px] flex-col gap-2 rounded-2xl border border-slate-100 p-2 text-left transition-colors hover:border-slate-300 hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-slate-300"
                  aria-label={`Add task on ${formatDateLabel(date)}`}
                >
                  <div className="text-center">
                    <div className="text-xs text-slate-500">{DAYS_OF_WEEK[dateObject.getDay()]}</div>
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
                            {task.planned_start_time} - {task.planned_duration_min}m
                          </div>
                        )}
                      </div>
                    ))}
                    {dayTasks.length === 0 && (
                      <div className="pt-4 text-center text-xs text-slate-300">-</div>
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

      {draft && (
        <div className="fixed inset-0 z-50 flex items-end bg-slate-950/30 p-4 backdrop-blur-sm sm:items-center sm:justify-center">
          <div className="w-full max-w-2xl rounded-2xl border border-slate-200 bg-white shadow-xl">
            <div className="flex items-start justify-between gap-4 border-b border-slate-200 p-5">
              <div>
                <div className="text-sm font-semibold text-slate-900">Add task</div>
                <div className="mt-0.5 text-sm text-slate-500">{formatDateLabel(draft.planned_date)}</div>
              </div>
              <button
                type="button"
                onClick={() => setDraft(null)}
                className="grid h-8 w-8 place-items-center rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-600"
                aria-label="Close"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                  <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                </svg>
              </button>
            </div>

            <div className="max-h-[75vh] overflow-y-auto p-5">
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className="mb-1.5 block text-xs font-medium text-slate-500">Task name</label>
                  <input
                    autoFocus
                    value={draft.title}
                    onChange={(event) => setDraft({ ...draft, title: event.target.value })}
                    onKeyDown={(event) => {
                      if (event.key === "Enter") handleCreateTask();
                    }}
                    className="w-full rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-slate-400"
                    placeholder="Study chapter 4"
                  />
                </div>
                <div>
                  <label className="mb-1.5 block text-xs font-medium text-slate-500">Category</label>
                  <select
                    value={draft.task_category}
                    onChange={(event) => setDraft({ ...draft, task_category: event.target.value })}
                    className="w-full cursor-pointer rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none"
                  >
                    {CATEGORIES.map((category) => (
                      <option key={category} value={category}>
                        {category}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="mt-4 grid gap-4 sm:grid-cols-3">
                <div>
                  <label className="mb-1.5 block text-xs font-medium text-slate-500">Date</label>
                  <input
                    type="date"
                    value={draft.planned_date}
                    onChange={(event) => setDraft({ ...draft, planned_date: event.target.value })}
                    className="w-full cursor-pointer rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-slate-400"
                  />
                </div>
                <TimePicker draft={draft} setDraft={setDraft} />
                <div>
                  <label className="mb-1.5 block text-xs font-medium text-slate-500">Duration</label>
                  <select
                    value={draft.planned_duration_min}
                    onChange={(event) => setDraft({ ...draft, planned_duration_min: event.target.value })}
                    className="w-full cursor-pointer rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none"
                  >
                    {[15, 30, 45, 60, 90, 120, 180].map((minutes) => (
                      <option key={minutes} value={minutes}>
                        {minutes} min
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="mt-4 grid gap-4 sm:grid-cols-3">
                <RatingDots
                  label="Importance"
                  value={draft.importance}
                  onChange={(value) => setDraft({ ...draft, importance: value })}
                />
                <RatingDots
                  label="Energy"
                  value={draft.energy_level}
                  onChange={(value) => setDraft({ ...draft, energy_level: value })}
                />
                <RatingDots
                  label="Focus"
                  value={draft.focus_level}
                  onChange={(value) => setDraft({ ...draft, focus_level: value })}
                />
              </div>

              {error && (
                <div className="mt-4 rounded-xl border border-rose-100 bg-rose-50 px-3 py-2 text-sm text-rose-700">
                  {error}
                </div>
              )}
            </div>

            <div className="flex justify-end gap-3 border-t border-slate-200 p-5">
              <button
                type="button"
                onClick={() => setDraft(null)}
                className="rounded-xl bg-slate-100 px-4 py-2.5 text-sm font-medium text-slate-600 transition-colors hover:bg-slate-200"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleCreateTask}
                disabled={saving}
                className="rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:opacity-60"
              >
                {saving ? "Saving..." : "Save task"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
