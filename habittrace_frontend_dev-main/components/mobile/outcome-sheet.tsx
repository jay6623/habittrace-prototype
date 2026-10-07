"use client";
import { useState } from "react";
import type { Task, OutcomeMeasurements } from "@/lib/api";
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
  "not_started" | "completed" | "partial" | "abandoned" | "in_progress";
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
    measurements?: OutcomeMeasurements,
  ) => Promise<void>;
}) {
  const [result, setResult] = useState<"partial" | "abandoned" | null>(null);
  const [actualStart, setActualStart] = useState("");
  const [actualEnd, setActualEnd] = useState(() => {
    const d = new Date();
    return `${localDateString(d)}T${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  });
  const [timeError, setTimeError] = useState<string | null>(null);
  const [progress, setProgress] = useState("");
  const [interruptions, setInterruptions] = useState("0");
  async function handleSelect(value: MobileResult, reason?: FailureReasonCode) {
    if (value === "in_progress") {
      await onSelect(value, reason);
      return;
    }
    const percent = Number(progress);
    const count = Number(interruptions);
    if (value !== "not_started" && (
      interruptions.trim() === "" || !Number.isInteger(count) || count < 0 || count > 10000
      || (value === "partial" && (progress.trim() === "" || !Number.isInteger(percent) || percent < 1 || percent > 99))
    )) {
      setTimeError("Enter an interruption count and, for partial progress, a completion percentage from 1 to 99.");
      return;
    }
    const measurements = {
      completion_ratio: value === "completed" ? 1 : value === "partial" ? percent / 100 : 0,
      interruption_count: value === "not_started" ? 0 : count,
    };
    setTimeError(null);
    if (value === "not_started" || isActive) {
      await onSelect(value, reason, undefined, measurements);
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
    }, measurements);
  }
  return (
    <Dialog title={task.title} onClose={onDismiss} busy={saving}>
      <p className="mb-4 text-sm text-slate-500">
        {isActive
          ? "Your start time is recorded. How did it go?"
          : "How did it go? You can record progress even when the plan changed."}
      </p>
      <label className="mb-4 block text-sm font-semibold">
        Times interrupted
        <input type="number" min="0" max="10000" step="1" inputMode="numeric"
          className="field mt-1" value={interruptions}
          onChange={(e) => setInterruptions(e.target.value)} disabled={saving} />
      </label>
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
          {result === "partial" && (
            <label className="mb-4 block text-sm font-semibold">
              How much did you complete? (%)
              <input type="number" min="1" max="99" step="1" inputMode="numeric"
                className="field mt-1" value={progress} placeholder="Enter 1–99"
                onChange={(e) => setProgress(e.target.value)} disabled={saving} />
            </label>
          )}
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
      {!isActive && !result && (
        <button className="btn-secondary mt-3 w-full" disabled={saving}
          onClick={() => void handleSelect("not_started")}>
          I didn’t start this plan
        </button>
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
