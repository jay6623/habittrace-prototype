"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { createTask, getTasks, type Task } from "@/lib/api";
import {
  formatTaskTime,
  localDateString,
  taskTimeInMinutes,
  toQuickTaskCreate,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import QuickAddForm from "./quick-add-form";

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

interface CalendarDay {
  date: Date;
  dateKey: string;
  inCurrentMonth: boolean;
}

function buildCalendarDays(month: Date): CalendarDay[] {
  const first = new Date(month.getFullYear(), month.getMonth(), 1, 12);
  const start = new Date(first);
  start.setDate(first.getDate() - first.getDay());

  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return {
      date,
      dateKey: localDateString(date),
      inCurrentMonth: date.getMonth() === month.getMonth(),
    };
  });
}

function taskSort(left: Task, right: Task): number {
  return taskTimeInMinutes(left.planned_start_time) - taskTimeInMinutes(right.planned_start_time);
}

function statusLabel(status: Task["task_status"]): string {
  if (status === "success") return "Completed";
  if (status === "failed") return "Not completed";
  return "Planned";
}

function readableError(caught: unknown): string {
  if (caught instanceof Error) {
    const message = caught.message.toLowerCase();
    if (caught.message.includes("401") || message.includes("sign in") || message.includes("session")) {
      return "Your session has expired. Please sign in again.";
    }
  }
  return "We couldn't load your calendar. Check your connection and try again.";
}

export default function MobileCalendar() {
  const today = localDateString();
  const [month, setMonth] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1, 12);
  });
  const [selectedDate, setSelectedDate] = useState(today);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [quickAddOpen, setQuickAddOpen] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const loadCalendar = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    try {
      setTasks(await getTasks());
    } catch (caught) {
      setLoadError(readableError(caught));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadCalendar();
  }, [loadCalendar]);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 3_500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const days = useMemo(() => buildCalendarDays(month), [month]);
  const tasksByDate = useMemo(() => {
    return tasks.reduce<Record<string, Task[]>>((grouped, task) => {
      const date = task.planned_date;
      if (!date) return grouped;
      (grouped[date] ??= []).push(task);
      return grouped;
    }, {});
  }, [tasks]);
  const selectedTasks = useMemo(
    () => [...(tasksByDate[selectedDate] ?? [])].sort(taskSort),
    [selectedDate, tasksByDate],
  );

  const monthLabel = month.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
  const selectedLabel = new Date(`${selectedDate}T12:00:00`).toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  });

  function moveMonth(offset: number) {
    setMonth((current) => new Date(current.getFullYear(), current.getMonth() + offset, 1, 12));
  }

  function selectToday() {
    const now = new Date();
    setMonth(new Date(now.getFullYear(), now.getMonth(), 1, 12));
    setSelectedDate(today);
  }

  function selectDay(day: CalendarDay) {
    setSelectedDate(day.dateKey);
    if (!day.inCurrentMonth) {
      setMonth(new Date(day.date.getFullYear(), day.date.getMonth(), 1, 12));
    }
  }

  async function handleQuickAdd(draft: QuickAddDraft) {
    const plansForDate = tasks.filter((task) => task.planned_date === draft.plannedDate);
    const created = await createTask(toQuickTaskCreate(draft, plansForDate.length + 1));
    setTasks((current) => [...current, created]);
    setSelectedDate(draft.plannedDate);
    const createdDate = new Date(`${draft.plannedDate}T12:00:00`);
    setMonth(new Date(createdDate.getFullYear(), createdDate.getMonth(), 1, 12));
    setQuickAddOpen(false);
    setToast(`Plan added for ${createdDate.toLocaleDateString("en-US", { month: "short", day: "numeric" })}.`);
  }

  return (
    <main
      className="mx-auto min-h-dvh w-full max-w-lg overflow-x-hidden bg-slate-50 px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] pt-[max(1rem,env(safe-area-inset-top))] text-slate-950"
      lang="en"
    >
      <header className="flex items-center justify-between gap-3 py-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-slate-400">HabitTrace</p>
          <h1 className="mt-1 text-2xl font-bold tracking-tight">Calendar</h1>
        </div>
        <div className="flex items-center gap-2">
          <button
            className="min-h-11 rounded-2xl bg-slate-950 px-3 text-sm font-bold text-white transition hover:bg-slate-800"
            onClick={() => setQuickAddOpen(true)}
            type="button"
          >
            + Add
          </button>
          <Link
            aria-label="Open account settings"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl bg-white text-xs font-bold text-slate-950 shadow-sm ring-1 ring-slate-200 hover:bg-slate-100"
            href="/dashboard/today/account"
          >
            HT
          </Link>
        </div>
      </header>

      <section aria-label="Monthly calendar" className="mt-3 rounded-3xl border border-slate-200 bg-white p-3 shadow-sm">
        <div className="flex items-center justify-between gap-2 px-1 pb-3">
          <button
            aria-label="Previous month"
            className="grid h-11 w-11 place-items-center rounded-full text-2xl text-slate-600 hover:bg-slate-100"
            onClick={() => moveMonth(-1)}
            type="button"
          >
            ‹
          </button>
          <button
            className="min-h-11 rounded-xl px-3 text-base font-bold hover:bg-slate-100"
            onClick={selectToday}
            type="button"
          >
            {monthLabel}
            <span className="ml-2 text-xs font-semibold text-emerald-700">Today</span>
          </button>
          <button
            aria-label="Next month"
            className="grid h-11 w-11 place-items-center rounded-full text-2xl text-slate-600 hover:bg-slate-100"
            onClick={() => moveMonth(1)}
            type="button"
          >
            ›
          </button>
        </div>

        <div className="grid grid-cols-7" role="row">
          {WEEKDAYS.map((weekday) => (
            <div className="py-2 text-center text-[11px] font-bold uppercase text-slate-400" key={weekday} role="columnheader">
              {weekday}
            </div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-y-1">
          {days.map((day) => {
            const dayTasks = tasksByDate[day.dateKey] ?? [];
            const selected = day.dateKey === selectedDate;
            const isToday = day.dateKey === today;
            return (
              <button
                aria-label={`${day.date.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}${dayTasks.length ? `, ${dayTasks.length} plans` : ""}`}
                aria-pressed={selected}
                className={`relative flex min-h-12 min-w-0 flex-col items-center justify-center rounded-2xl text-sm font-semibold transition ${
                  selected
                    ? "bg-slate-950 text-white"
                    : day.inCurrentMonth
                      ? "text-slate-800 hover:bg-slate-100"
                      : "text-slate-300 hover:bg-slate-50"
                }`}
                key={day.dateKey}
                onClick={() => selectDay(day)}
                type="button"
              >
                <span className={isToday && !selected ? "text-emerald-700" : undefined}>
                  {day.date.getDate()}
                </span>
                <span className="mt-1 flex h-1.5 items-center gap-0.5" aria-hidden="true">
                  {dayTasks.slice(0, 3).map((task) => (
                    <span
                      className={`h-1.5 w-1.5 rounded-full ${selected ? "bg-emerald-300" : task.task_status === "pending" ? "bg-slate-700" : "bg-slate-300"}`}
                      key={task.id}
                    />
                  ))}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      <section aria-labelledby="selected-date-title" className="mt-6">
        <div className="mb-3 flex items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold" id="selected-date-title">{selectedLabel}</h2>
            <p className="mt-0.5 text-xs font-medium text-slate-500">
              {selectedTasks.length} {selectedTasks.length === 1 ? "plan" : "plans"}
            </p>
          </div>
          <button
            aria-label={`Add a plan on ${selectedLabel}`}
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full border border-slate-300 bg-white text-2xl text-slate-900 shadow-sm hover:bg-slate-100"
            onClick={() => setQuickAddOpen(true)}
            type="button"
          >
            +
          </button>
        </div>

        {loading ? (
          <div aria-label="Loading calendar plans" className="space-y-3" role="status">
            <div className="h-20 animate-pulse rounded-2xl bg-slate-200" />
            <div className="h-20 animate-pulse rounded-2xl bg-slate-200" />
          </div>
        ) : loadError ? (
          <div className="rounded-2xl border border-rose-200 bg-white p-5 text-center" role="alert">
            <p className="text-sm font-medium text-rose-700">{loadError}</p>
            <button
              className="mt-4 min-h-11 rounded-xl bg-slate-950 px-5 text-sm font-bold text-white"
              onClick={() => void loadCalendar()}
              type="button"
            >
              Try again
            </button>
          </div>
        ) : selectedTasks.length === 0 ? (
          <button
            className="min-h-24 w-full rounded-2xl border border-dashed border-slate-300 bg-white px-5 text-center text-sm font-semibold text-slate-500 hover:border-slate-500 hover:text-slate-800"
            onClick={() => setQuickAddOpen(true)}
            type="button"
          >
            No plans yet. Tap to add one.
          </button>
        ) : (
          <ul className="space-y-3">
            {selectedTasks.map((task) => (
              <li className="flex items-center gap-3 rounded-2xl border border-slate-200 bg-white p-4" key={task.id}>
                <div className={`h-11 w-1 shrink-0 rounded-full ${task.task_status === "pending" ? "bg-slate-950" : "bg-slate-300"}`} />
                <div className="min-w-0 flex-1">
                  <p className={`truncate font-bold ${task.task_status === "pending" ? "text-slate-900" : "text-slate-500 line-through"}`}>
                    {task.title}
                  </p>
                  <p className="mt-1 text-xs font-medium text-slate-500">
                    {formatTaskTime(task.planned_start_time)} · {task.planned_duration_min} min
                  </p>
                </div>
                <span className="shrink-0 text-[11px] font-bold text-slate-400">
                  {statusLabel(task.task_status)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {toast && (
        <div aria-live="polite" className="fixed left-1/2 top-[max(1rem,env(safe-area-inset-top))] z-[60] w-[calc(100%-2rem)] max-w-md -translate-x-1/2 rounded-2xl bg-emerald-600 px-4 py-3 text-center text-sm font-bold text-white shadow-xl" role="status">
          {toast}
        </div>
      )}

      {quickAddOpen && (
        <QuickAddForm
          initialDate={selectedDate}
          onDismiss={() => setQuickAddOpen(false)}
          onSubmit={handleQuickAdd}
        />
      )}
    </main>
  );
}
