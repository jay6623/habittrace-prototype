"use client";

import { useEffect, useId, useRef, useState } from "react";

const WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

function parseDate(value: string): Date {
  const [year, month, day] = value.split("-").map(Number);
  return new Date(year, month - 1, day, 12);
}

function toDateValue(date: Date): string {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function todayValue(): string {
  return toDateValue(new Date());
}

function formatSelectedDate(value: string): string {
  return parseDate(value).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function DatePicker({
  value,
  onChange,
  required = false,
  ariaLabel = "Choose date",
}: {
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  ariaLabel?: string;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const panelId = useId();
  const [open, setOpen] = useState(false);
  const [visibleMonth, setVisibleMonth] = useState(() => {
    const selected = value ? parseDate(value) : new Date();
    return new Date(selected.getFullYear(), selected.getMonth(), 1, 12);
  });

  useEffect(() => {
    if (!open) return;
    function closeOnOutsideClick(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("pointerdown", closeOnOutsideClick);
    return () => document.removeEventListener("pointerdown", closeOnOutsideClick);
  }, [open]);

  function changeMonth(offset: number) {
    setVisibleMonth(
      (current) =>
        new Date(current.getFullYear(), current.getMonth() + offset, 1, 12),
    );
  }

  function selectDate(date: Date) {
    onChange(toDateValue(date));
    setOpen(false);
  }

  const year = visibleMonth.getFullYear();
  const month = visibleMonth.getMonth();
  const firstWeekday = new Date(year, month, 1, 12).getDay();
  const gridStart = new Date(year, month, 1 - firstWeekday, 12);
  const days = Array.from({ length: 42 }, (_, index) => {
    const date = new Date(gridStart);
    date.setDate(gridStart.getDate() + index);
    return date;
  });
  const today = todayValue();

  return (
    <div ref={rootRef} className="relative">
      <input
        className="sr-only"
        tabIndex={-1}
        required={required}
        value={value}
        onChange={() => undefined}
        aria-hidden="true"
      />
      <button
        type="button"
        aria-label={ariaLabel}
        aria-expanded={open}
        aria-controls={panelId}
        onClick={() => {
          if (!open && value) {
            const selected = parseDate(value);
            setVisibleMonth(
              new Date(selected.getFullYear(), selected.getMonth(), 1, 12),
            );
          }
          setOpen((current) => !current);
        }}
        className="field flex items-center justify-between gap-3 text-left transition hover:border-slate-400 hover:bg-slate-50"
      >
        <span className={value ? "text-slate-800" : "text-slate-400"}>
          {value ? formatSelectedDate(value) : "Choose a date"}
        </span>
        <svg
          aria-hidden="true"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          className="h-5 w-5 shrink-0 text-emerald-600"
        >
          <path d="M7 3v3m10-3v3M4.5 9.5h15M6.5 5h11a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2Z" />
        </svg>
      </button>

      {open && (
        <div
          id={panelId}
          role="dialog"
          aria-label="Calendar"
          onKeyDown={(event) => {
            if (event.key === "Escape") setOpen(false);
          }}
          className="absolute left-0 top-[calc(100%+.55rem)] z-30 w-[min(20rem,calc(100vw-4rem))] rounded-2xl border border-slate-200 bg-white p-3 shadow-[0_18px_50px_-18px_rgb(15_23_42/0.35)]"
        >
          <div className="flex items-center justify-between px-1 pb-3">
            <button
              type="button"
              aria-label="Previous month"
              onClick={() => changeMonth(-1)}
              className="grid h-9 w-9 place-items-center rounded-xl text-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-950"
            >
              ‹
            </button>
            <div className="text-sm font-bold text-slate-900">
              {visibleMonth.toLocaleDateString("en-US", {
                month: "long",
                year: "numeric",
              })}
            </div>
            <button
              type="button"
              aria-label="Next month"
              onClick={() => changeMonth(1)}
              className="grid h-9 w-9 place-items-center rounded-xl text-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-950"
            >
              ›
            </button>
          </div>

          <div className="grid grid-cols-7 gap-0.5">
            {WEEKDAYS.map((day) => (
              <div
                key={day}
                className="grid h-8 place-items-center text-[11px] font-bold uppercase tracking-wider text-slate-400"
              >
                {day}
              </div>
            ))}
            {days.map((date) => {
              const dateValue = toDateValue(date);
              const selected = dateValue === value;
              const isToday = dateValue === today;
              const outsideMonth = date.getMonth() !== month;
              return (
                <button
                  key={dateValue}
                  type="button"
                  aria-label={date.toLocaleDateString("en-US", {
                    weekday: "long",
                    month: "long",
                    day: "numeric",
                    year: "numeric",
                  })}
                  aria-pressed={selected}
                  onClick={() => selectDate(date)}
                  className={`relative grid aspect-square place-items-center rounded-xl text-sm font-semibold transition ${
                    selected
                      ? "bg-slate-950 text-white shadow-sm"
                      : outsideMonth
                        ? "text-slate-300 hover:bg-slate-50 hover:text-slate-500"
                        : "text-slate-700 hover:bg-emerald-50 hover:text-emerald-800"
                  }`}
                >
                  {date.getDate()}
                  {isToday && !selected && (
                    <span className="absolute bottom-1 h-1 w-1 rounded-full bg-emerald-500" />
                  )}
                </button>
              );
            })}
          </div>

          <button
            type="button"
            onClick={() => selectDate(new Date())}
            className="mt-2 w-full rounded-xl bg-emerald-50 px-3 py-2.5 text-sm font-bold text-emerald-800 transition hover:bg-emerald-100"
          >
            Jump to today
          </button>
        </div>
      )}
    </div>
  );
}
