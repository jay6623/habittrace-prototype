"use client";
import { useState } from "react";
import type { Task } from "@/lib/api";
import {
  FAILURE_REASONS,
  localDateString,
  type FailureReasonCode,
} from "@/lib/mobile-task";
import Dialog from "@/components/ui/dialog";
function isFutureTime(end: Date) { return end.getTime() > Date.now() + 300000; }

export interface OutcomeTimes {
  actual_start_time: string;
  actual_end_time: string;
}
export type MobileResult =
  "completed" | "partial" | "abandoned" | "in_progress";
export default function OutcomeSheet({
  task,
  isActive,
  error,
  saving,
  onDismiss,
  onSelect,
}: {
  task: Task;
  isActive: boolean;
  error: string | null;
  saving: boolean;
  onDismiss: () => void;
  onSelect: (
    result: MobileResult,
    reason?: FailureReasonCode,
    times?: OutcomeTimes,
  ) => Promise<void>;
}) {
  const [result, setResult] = useState<"partial" | "abandoned" | null>(null);
  const [actualStart, setActualStart] = useState("");
  const [actualEnd, setActualEnd] = useState(() => {
    const d = new Date();
    return `${localDateString(d)}T${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  });
  const [timeError, setTimeError] = useState<string | null>(null);
  async function handleSelect(value: MobileResult, reason?: FailureReasonCode) {
    if (value === "in_progress" || isActive) {
      await onSelect(value, reason);
      return;
    }
    const start = new Date(actualStart),
      end = new Date(actualEnd);
    if (
      !actualStart ||
      !actualEnd ||
      Number.isNaN(start.getTime()) ||
      Number.isNaN(end.getTime()) ||
      start > end ||
      isFutureTime(end)
    ) {
      setTimeError(
        "Enter when you actually started and finished. The end must follow the start and cannot be in the future.",
      );
      return;
    }
    setTimeError(null);
    await onSelect(value, reason, {
      actual_start_time: start.toISOString(),
      actual_end_time: end.toISOString(),
    });
  }
  return (
    <Dialog title={task.title} onClose={onDismiss} busy={saving}>
      <p className="mb-4 text-sm text-slate-500">
        {isActive
          ? "Your start time is recorded. How did it go?"
          : "How did it go? You can record progress even when the plan changed."}
      </p>
      {!isActive && (
        <fieldset className="mb-5 space-y-3 rounded-xl bg-slate-50 p-4">
          <legend className="text-sm font-semibold">
            Forgot to start the timer?
          </legend>
          <p className="text-xs text-slate-500">
            Enter your actual times to record a past outcome. Choose “Still
            working” to start now.
          </p>
          <label className="block text-sm">
            Started
            <input
              type="datetime-local"
              className="field mt-1"
              value={actualStart}
              onChange={(e) => setActualStart(e.target.value)}
            />
          </label>
          <label className="block text-sm">
            Finished
            <input
              type="datetime-local"
              className="field mt-1"
              value={actualEnd}
              onChange={(e) => setActualEnd(e.target.value)}
            />
          </label>
        </fieldset>
      )}
      {timeError && (
        <p role="alert" className="mb-4 text-sm text-rose-700">
          {timeError}
        </p>
      )}
      {result ? (
        <>
          <button
            className="btn-secondary mb-4"
            disabled={saving}
            onClick={() => setResult(null)}
          >
            ← Back
          </button>
          <p className="mb-3 font-semibold">What got in the way?</p>
          <div className="grid grid-cols-2 gap-2">
            {FAILURE_REASONS.map((reason) => (
              <button
                key={reason.code}
                disabled={saving}
                className="min-h-14 rounded-xl border border-slate-200 p-3 text-left text-sm hover:bg-slate-50"
                onClick={() => void handleSelect(result, reason.code)}
              >
                {reason.label}
              </button>
            ))}
          </div>
        </>
      ) : (
        <div className="grid grid-cols-2 gap-3">
          {[
            {
              value: "completed",
              title: "Completed",
              detail: "I finished my plan",
              style: "bg-emerald-50 border-emerald-200",
            },
            {
              value: "partial",
              title: "Partly completed",
              detail: "I made some progress",
              style: "bg-amber-50 border-amber-200",
            },
            {
              value: "abandoned",
              title: "Not this time",
              detail: "I couldn’t finish",
              style: "bg-slate-50 border-slate-200",
            },
            {
              value: "in_progress",
              title: "Still working",
              detail: "Keep the plan active",
              style: "bg-sky-50 border-sky-200",
            },
          ].map((option) => (
            <button
              key={option.value}
              className={`min-h-24 rounded-2xl border p-4 text-left ${option.style}`}
              disabled={saving}
              onClick={() =>
                option.value === "partial" || option.value === "abandoned"
                  ? setResult(option.value)
                  : void handleSelect(option.value as MobileResult)
              }
            >
              <span className="block font-semibold">{option.title}</span>
              <span className="mt-1 block text-sm text-slate-600">
                {option.detail}
              </span>
            </button>
          ))}
        </div>
      )}
      {saving && (
        <p role="status" className="mt-4 text-sm">
          Saving outcome…
        </p>
      )}
      {error && (
        <p
          role="alert"
          className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
        >
          {error}
        </p>
      )}
    </Dialog>
  );
}
