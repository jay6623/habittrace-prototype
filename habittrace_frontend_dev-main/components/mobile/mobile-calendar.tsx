"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Dialog from "@/components/ui/dialog";
import PlanEditForm from "./plan-edit-form";
import { useDataRefresh } from "@/lib/refresh";
import PlanFilters, { ALL_PLAN_FILTERS, matchesPlanFilters } from "@/components/layout/plan-filters";
import { createTask, getTasks, type Task } from "@/lib/api";
import {
  formatScheduledRange,
  localDateString,
  taskTimeInMinutes,
  toQuickTaskCreate,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import QuickAddForm from "./quick-add-form";
import { useToast } from "@/components/ui/toast";

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
  return (
    taskTimeInMinutes(left.planned_start_time) -
    taskTimeInMinutes(right.planned_start_time)
  );
}

function statusLabel(status: Task["task_status"]): string {
  if (status === "success") return "Completed";
  if (status === "failed") return "Not completed";
  return "Planned";
}

function readableError(caught: unknown): string {
  if (caught instanceof Error) {
    const message = caught.message.toLowerCase();
    if (
      caught.message.includes("401") ||
      message.includes("sign in") ||
      message.includes("session")
    ) {
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
  const inbox = useToast();
  const [editing, setEditing] = useState<Task | null>(null);
  const [filters, setFilters] = useState(ALL_PLAN_FILTERS);
  const [optionsOpen, setOptionsOpen] = useState(false);
  const [view, setView] = useState<"month" | "week">("month");

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

  useDataRefresh(loadCalendar);

  const days = useMemo(() => buildCalendarDays(month), [month]);
  const selectedDayIndex = days.findIndex((day) => day.dateKey === selectedDate);
  const weekIndex = Math.max(0, Math.floor(selectedDayIndex / 7));
  const visibleDays = view === "month" ? days : days.slice(weekIndex * 7, weekIndex * 7 + 7);
  const tasksByDate = useMemo(() => {
    return tasks.reduce<Record<string, Task[]>>((grouped, task) => {
      if (!matchesPlanFilters(task, filters)) return grouped;
      const date = task.planned_date;
      if (!date) return grouped;
      (grouped[date] ??= []).push(task);
      return grouped;
    }, {});
  }, [tasks, filters]);
  const selectedTasks = useMemo(
    () => [...(tasksByDate[selectedDate] ?? [])].sort(taskSort),
    [selectedDate, tasksByDate],
  );

  const monthLabel = month.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
  const selectedLabel = new Date(`${selectedDate}T12:00:00`).toLocaleDateString(
    "en-US",
    {
      weekday: "long",
      month: "long",
      day: "numeric",
    },
  );

  function moveMonth(offset: number) {
    if (view === "week") {
      const next = new Date(`${selectedDate}T12:00:00`);
      next.setDate(next.getDate() + offset * 7);
      setSelectedDate(localDateString(next));
      setMonth(new Date(next.getFullYear(), next.getMonth(), 1, 12));
      return;
    }
    const next = new Date(month.getFullYear(), month.getMonth() + offset, 1, 12);
    setMonth(next);
    setSelectedDate(localDateString(next));
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
    const plansForDate = tasks.filter(
      (task) => task.planned_date === draft.plannedDate,
    );
    const created = await createTask(
      toQuickTaskCreate(draft, plansForDate.length + 1),
    );
    setTasks((current) => [...current, created]);
    setSelectedDate(draft.plannedDate);
    const createdDate = new Date(`${draft.plannedDate}T12:00:00`);
    setMonth(
      new Date(createdDate.getFullYear(), createdDate.getMonth(), 1, 12),
    );
    setQuickAddOpen(false);
    const message = `Plan added for ${createdDate.toLocaleDateString("en-US", { month: "short", day: "numeric" })}.`;
    setToast(message);
    inbox.record("success", message);
  }

  return (
    <div
      className="mx-auto w-full max-w-lg text-slate-950"
      lang="en"
    >
      <header className="flex flex-wrap items-center justify-between gap-2 pb-2">
        <div>

          <h1 className="text-xl font-bold tracking-tight">Calendar</h1>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" onClick={selectToday} className="btn-secondary">Today</button>
          <button
            className="min-h-11 rounded-2xl bg-slate-950 px-3 text-sm font-bold text-white transition hover:bg-slate-800"
            onClick={() => setQuickAddOpen(true)}
            type="button"
          >
            + Add
          </button>
          <button type="button" aria-label="Calendar view and filters" aria-haspopup="dialog" onClick={() => setOptionsOpen(true)} className="btn-secondary min-w-11 px-2">...</button>
        </div>
      </header>

      <section
        aria-label="Monthly calendar"
        className="rounded-3xl border border-slate-200 bg-white p-3 shadow-sm"
      >
        <div className="flex items-center justify-between gap-1 pb-1">
          <button
            aria-label={view === "month" ? "Previous month" : "Previous week"}
            className="grid h-11 w-11 place-items-center rounded-full text-2xl text-slate-600 hover:bg-slate-100"
            onClick={() => moveMonth(-1)}
            type="button"
          >
            ‹
          </button>
          <h2 className="min-w-0 text-center text-sm font-bold" aria-live="polite">{monthLabel}</h2>
          <button
            aria-label={view === "month" ? "Next month" : "Next week"}
            className="grid h-11 w-11 place-items-center rounded-full text-2xl text-slate-600 hover:bg-slate-100"
            onClick={() => moveMonth(1)}
            type="button"
          >
            ›
          </button>
        </div>

        <div className="grid grid-cols-7" role="row">
          {WEEKDAYS.map((weekday) => (
            <div
              className="py-2 text-center text-[11px] font-bold uppercase text-slate-400"
              key={weekday}
              role="columnheader"
            >
              {weekday}
            </div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-y-0.5">
          {visibleDays.map((day) => {
            const dayTasks = tasksByDate[day.dateKey] ?? [];
            const selected = day.dateKey === selectedDate;
            const isToday = day.dateKey === today;
            return (
              <button
                aria-label={`${day.date.toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" })}${dayTasks.length ? `, ${dayTasks.length} plans` : ""}`}
                aria-pressed={selected}
                aria-current={isToday ? "date" : undefined}
                className={`relative flex min-h-11 min-w-0 flex-col items-center justify-center rounded-2xl text-sm font-semibold transition ${
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
                <span
                  className={
                    isToday ? "rounded-full ring-2 ring-emerald-500 px-1" : undefined
                  }
                >
                  {day.date.getDate()}
                </span>
                <span
                  className="mt-1 flex h-1.5 items-center gap-0.5"
                  aria-hidden="true"
                >
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

      <section aria-labelledby="selected-date-title" className="mt-3">
        <div className="mb-3 flex items-center justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold" id="selected-date-title">
              {selectedLabel}
            </h2>
            <p className="mt-0.5 text-xs font-medium text-slate-500">
              {filters.category !== "all" || filters.priority !== "all" ? "Filtered: " : ""}{selectedTasks.length}{" "}
              {selectedTasks.length === 1 ? "plan" : "plans"}
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

        {loadError && tasks.length > 0 && <p role="alert" className="mb-3 text-sm text-rose-700">{loadError} <button type="button" className="underline" onClick={() => void loadCalendar()}>Retry</button></p>}
        {loading && tasks.length === 0 ? (
          <div
            aria-label="Loading calendar plans"
            className="space-y-3"
            role="status"
          >
            <div className="h-20 animate-pulse rounded-2xl bg-slate-200" />
            <div className="h-20 animate-pulse rounded-2xl bg-slate-200" />
          </div>
        ) : loadError && tasks.length === 0 ? (
          <div
            className="rounded-2xl border border-rose-200 bg-white p-5 text-center"
            role="alert"
          >
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
            {filters.category !== "all" || filters.priority !== "all" ? "No matching plans. Change filters or add a plan." : "No plans yet. Tap to add one."}
          </button>
        ) : (
          <ul className="max-h-[45dvh] space-y-3 overflow-y-auto overscroll-contain pb-16" aria-label="Selected day plans">
            {selectedTasks.map((task) => (
              <li
                key={task.id}
              >
                <button type="button" onClick={() => setEditing(task)} aria-label={`Edit ${task.title}`}
                  className="flex min-h-16 w-full items-center gap-3 rounded-2xl border border-slate-200 bg-white p-3 text-left hover:bg-slate-100">
                <div
                  className={`h-11 w-1 shrink-0 rounded-full ${task.task_status === "pending" ? "bg-slate-950" : "bg-slate-300"}`}
                />
                <div className="min-w-0 flex-1">
                  <p
                    className={`break-words font-bold ${task.task_status === "pending" ? "text-slate-900" : "text-slate-500 line-through"}`}
                  >
                    {task.title}
                  </p>
                  <p className="mt-1 text-xs font-medium text-slate-500">
                    {formatScheduledRange(task.planned_start_time, task.planned_duration_min)}
                  </p>
                </div>
                <span className="shrink-0 text-[11px] font-bold text-slate-400">
                  {statusLabel(task.task_status)}
                </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>

      {toast && (
        <div
          aria-live="polite"
          className="fixed left-1/2 top-[max(1rem,env(safe-area-inset-top))] z-[60] w-[calc(100%-2rem)] max-w-md -translate-x-1/2 rounded-2xl bg-emerald-600 px-4 py-3 text-center text-sm font-bold text-white shadow-xl"
          role="status"
        >
          {toast}
        </div>
      )}

      {optionsOpen && <Dialog title="Calendar view and filters" onClose={() => setOptionsOpen(false)}>
        <div className="mb-3 flex gap-2" aria-label="Calendar view">
          {(["month", "week"] as const).map((mode) => <button key={mode} type="button" aria-pressed={view === mode} className={view === mode ? "btn-primary capitalize" : "btn-secondary capitalize"} onClick={() => setView(mode)}>{mode}</button>)}
        </div>
        <div className="flex flex-wrap gap-2 pb-3"><PlanFilters filters={filters} onChange={setFilters} tone="slate" /></div>
        <button type="button" className="btn-primary mt-3 w-full" onClick={() => setOptionsOpen(false)}>Done</button>
      </Dialog>}
      {editing && <PlanEditForm key={editing.id} task={editing} onDismiss={() => setEditing(null)} onSaved={(saved) => {
        setTasks((items) => items.map((item) => item.id === saved.id ? saved : item));
        setSelectedDate(saved.planned_date);
        const date = new Date(`${saved.planned_date}T12:00:00`);
        setMonth(new Date(date.getFullYear(), date.getMonth(), 1, 12));
        setEditing(null); setToast("Plan updated.");
      }} />}
      {quickAddOpen && (
        <QuickAddForm
          initialDate={selectedDate}
          onDismiss={() => setQuickAddOpen(false)}
          onSubmit={handleQuickAdd}
        />
      )}
    </div>
  );
}
