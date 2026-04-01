"use client";

import { useState, useEffect } from "react";
import { getTasks, type Task } from "@/lib/api";

// ── Color Map by category ──────────────────────────────
const categoryChipColors: Record<string, string> = {
  Study:             "bg-sky-100 text-sky-800",
  Work:              "bg-violet-100 text-violet-800",
  Chores:            "bg-amber-100 text-amber-800",
  "Fitness/Health":  "bg-emerald-100 text-emerald-800",
  "Errands/Admin":   "bg-slate-100 text-slate-700",
  "Hobbies/Leisure": "bg-rose-100 text-rose-800",
  Social:            "bg-indigo-100 text-indigo-800",
  Other:             "bg-gray-100 text-gray-700",
};

// ── Helpers ────────────────────────────────────────────
const DAYS_OF_WEEK = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function getDaysInMonth(year: number, month: number) {
  return new Date(year, month + 1, 0).getDate();
}

function getFirstDayOfMonth(year: number, month: number) {
  return new Date(year, month, 1).getDay();
}

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

// ── Component ──────────────────────────────────────────
export default function CalendarPage() {
  const today = new Date();
  const [year, setYear] = useState(today.getFullYear());
  const [month, setMonth] = useState(today.getMonth());
  const [view, setView] = useState<"month" | "week">("month");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  // Fetch all tasks (no date filter) and group by planned_date
  useEffect(() => {
    setLoading(true);
    getTasks()
      .then(setTasks)
      .catch(() => setTasks([]))
      .finally(() => setLoading(false));
  }, []);

  const daysInMonth = getDaysInMonth(year, month);
  const firstDay = getFirstDayOfMonth(year, month);

  // Previous month trailing days
  const prevMonthDays = getDaysInMonth(year, month - 1);
  const trailingDays = Array.from(
    { length: firstDay },
    (_, i) => prevMonthDays - firstDay + 1 + i
  );

  // Current month days
  const currentDays = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  // Next month leading days (fill to complete the grid row)
  const totalCells = trailingDays.length + currentDays.length;
  const remainingCells = totalCells % 7 === 0 ? 0 : 7 - (totalCells % 7);
  const leadingDays = Array.from({ length: remainingCells }, (_, i) => i + 1);

  function goToPrevMonth() {
    if (month === 0) { setMonth(11); setYear(year - 1); }
    else setMonth(month - 1);
  }

  function goToNextMonth() {
    if (month === 11) { setMonth(0); setYear(year + 1); }
    else setMonth(month + 1);
  }

  // Build YYYY-MM-DD string for a given day in the current view month
  function dateStr(day: number) {
    const mm = String(month + 1).padStart(2, "0");
    const dd = String(day).padStart(2, "0");
    return `${year}-${mm}-${dd}`;
  }

  function getTasksForDay(day: number): Task[] {
    const ds = dateStr(day);
    return tasks.filter((t) => t.planned_date === ds);
  }

  // Status dot color
  function statusBg(status: Task["task_status"]) {
    if (status === "success") return "bg-emerald-100 text-emerald-800";
    if (status === "failed")  return "bg-rose-100 text-rose-800";
    return categoryChipColors[tasks[0]?.task_category] ?? "bg-slate-100 text-slate-700";
  }

  function taskChipColor(task: Task) {
    if (task.task_status === "success") return "bg-emerald-100 text-emerald-800";
    if (task.task_status === "failed")  return "bg-rose-100 text-rose-800";
    return categoryChipColors[task.task_category] ?? "bg-slate-100 text-slate-700";
  }

  // ── Week view: show days of the current week ──────────────────────────────
  function getCurrentWeekDays() {
    const todayDate = new Date(year, month, today.getDate());
    const dayOfWeek = todayDate.getDay();
    const sunday = new Date(todayDate);
    sunday.setDate(todayDate.getDate() - dayOfWeek);
    return Array.from({ length: 7 }, (_, i) => {
      const d = new Date(sunday);
      d.setDate(sunday.getDate() + i);
      return d;
    });
  }

  const weekDays = getCurrentWeekDays();

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="text-sm text-slate-500">Calendar</div>
          <h1 className="text-2xl font-bold">Task Calendar</h1>
        </div>

        <div className="flex items-center gap-3">
          {/* Month navigation */}
          <div className="flex items-center gap-2">
            <button
              onClick={goToPrevMonth}
              className="h-9 w-9 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 grid place-items-center"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
            <span className="text-sm font-semibold min-w-[140px] text-center">
              {MONTH_NAMES[month]} {year}
            </span>
            <button
              onClick={goToNextMonth}
              className="h-9 w-9 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 grid place-items-center"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path d="M9 18l6-6-6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          </div>

          {/* View toggle */}
          <div className="flex rounded-xl border border-slate-200 overflow-hidden">
            <button
              onClick={() => setView("month")}
              className={`px-4 py-2 text-sm font-medium transition-colors ${
                view === "month"
                  ? "bg-white text-slate-900"
                  : "bg-slate-50 text-slate-500 hover:text-slate-700"
              }`}
            >
              Month
            </button>
            <button
              onClick={() => setView("week")}
              className={`px-4 py-2 text-sm font-medium border-l border-slate-200 transition-colors ${
                view === "week"
                  ? "bg-white text-slate-900"
                  : "bg-slate-50 text-slate-500 hover:text-slate-700"
              }`}
            >
              Week
            </button>
          </div>
        </div>
      </div>

      {/* Loading */}
      {loading && (
        <div className="text-center py-4 text-sm text-slate-400 animate-pulse">
          Loading tasks…
        </div>
      )}

      {/* ── Month View ── */}
      {view === "month" && (
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          {/* Day headers */}
          <div className="grid grid-cols-7 gap-3 mb-3">
            {DAYS_OF_WEEK.map((day) => (
              <div key={day} className="text-center text-sm font-medium text-slate-500">
                {day}
              </div>
            ))}
          </div>

          {/* Calendar cells */}
          <div className="grid grid-cols-7 gap-3">
            {/* Previous month (greyed out) */}
            {trailingDays.map((day) => (
              <div
                key={`prev-${day}`}
                className="min-h-[92px] rounded-2xl border border-slate-100 bg-slate-50/50 p-2"
              >
                <span className="text-sm text-slate-300">{day}</span>
              </div>
            ))}

            {/* Current month */}
            {currentDays.map((day) => {
              const dayTasks = getTasksForDay(day);
              const isToday =
                day === today.getDate() &&
                month === today.getMonth() &&
                year === today.getFullYear();

              return (
                <div
                  key={`curr-${day}`}
                  className={`min-h-[92px] rounded-2xl border p-2 transition-colors hover:border-slate-300 ${
                    isToday
                      ? "border-slate-900 bg-slate-50"
                      : "border-slate-200 bg-white"
                  }`}
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
                      className={`mt-1.5 rounded-lg px-2 py-1 text-xs font-medium truncate ${taskChipColor(task)}`}
                      title={task.title}
                    >
                      {task.planned_start_time && (
                        <span className="opacity-60 mr-1">{task.planned_start_time}</span>
                      )}
                      {task.title}
                    </div>
                  ))}
                  {dayTasks.length > 3 && (
                    <div className="mt-1 text-xs text-slate-400 pl-2">
                      +{dayTasks.length - 3} more
                    </div>
                  )}
                </div>
              );
            })}

            {/* Next month (greyed out) */}
            {leadingDays.map((day) => (
              <div
                key={`next-${day}`}
                className="min-h-[92px] rounded-2xl border border-slate-100 bg-slate-50/50 p-2"
              >
                <span className="text-sm text-slate-300">{day}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── Week View ── */}
      {view === "week" && (
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="grid grid-cols-7 gap-3">
            {weekDays.map((d) => {
              const ds = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
              const dayTasks = tasks.filter((t) => t.planned_date === ds);
              const isToday =
                d.getDate() === today.getDate() &&
                d.getMonth() === today.getMonth() &&
                d.getFullYear() === today.getFullYear();

              return (
                <div key={ds} className="flex flex-col gap-2">
                  {/* Day header */}
                  <div className="text-center">
                    <div className="text-xs text-slate-500">{DAYS_OF_WEEK[d.getDay()]}</div>
                    <div
                      className={`mx-auto mt-1 h-8 w-8 rounded-full flex items-center justify-center text-sm font-semibold ${
                        isToday
                          ? "bg-slate-900 text-white"
                          : "text-slate-700"
                      }`}
                    >
                      {d.getDate()}
                    </div>
                  </div>

                  {/* Tasks */}
                  <div className="min-h-[120px] rounded-2xl border border-slate-100 p-2 space-y-1.5">
                    {dayTasks.map((task) => (
                      <div
                        key={task.id}
                        className={`rounded-lg px-2 py-1.5 text-xs font-medium ${taskChipColor(task)}`}
                      >
                        <div className="truncate">{task.title}</div>
                        {task.planned_start_time && (
                          <div className="opacity-60 mt-0.5">{task.planned_start_time} · {task.planned_duration_min}m</div>
                        )}
                      </div>
                    ))}
                    {dayTasks.length === 0 && (
                      <div className="text-xs text-slate-300 text-center pt-4">—</div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Legend */}
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
    </div>
  );
}
