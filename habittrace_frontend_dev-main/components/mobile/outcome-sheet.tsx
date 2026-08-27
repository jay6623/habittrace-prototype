"use client";

import { useEffect, useState } from "react";
import type { Task } from "@/lib/api";
import {
  FAILURE_REASONS,
  type FailureReasonCode,
} from "@/lib/mobile-task";

export type MobileResult = "completed" | "partial" | "abandoned" | "in_progress";

interface OutcomeSheetProps {
  task: Task;
  isActive: boolean;
  error: string | null;
  saving: boolean;
  onDismiss: () => void;
  onSelect: (result: MobileResult, reason?: FailureReasonCode) => Promise<void>;
}

const RESULT_OPTIONS: Array<{
  value: MobileResult;
  label: string;
  detail: string;
  style: string;
}> = [
  {
    value: "completed",
    label: "Completed",
    detail: "I finished what I planned",
    style: "border-emerald-200 bg-emerald-50 text-emerald-900",
  },
  {
    value: "partial",
    label: "Partially done",
    detail: "I made some progress",
    style: "border-amber-200 bg-amber-50 text-amber-950",
  },
  {
    value: "abandoned",
    label: "Not completed",
    detail: "I couldn't finish this time",
    style: "border-rose-200 bg-rose-50 text-rose-950",
  },
  {
    value: "in_progress",
    label: "Still in progress",
    detail: "Keep this plan active",
    style: "border-sky-200 bg-sky-50 text-sky-950",
  },
];

export default function OutcomeSheet({
  task,
  isActive,
  error,
  saving,
  onDismiss,
  onSelect,
}: OutcomeSheetProps) {
  const [resultNeedingReason, setResultNeedingReason] = useState<
    "partial" | "abandoned" | null
  >(null);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !saving) onDismiss();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onDismiss, saving]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/45 px-0 sm:px-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !saving) onDismiss();
      }}
    >
      <section
        aria-labelledby="outcome-title"
        aria-modal="true"
        className="w-full max-w-lg rounded-t-3xl bg-white px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-5 shadow-2xl sm:mb-4 sm:rounded-3xl"
        role="dialog"
      >
        <div className="mb-5 flex items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-xs font-semibold text-slate-500">
              {isActive ? "ACTIVE PLAN" : "PLAN OUTCOME"}
            </p>
            <h2 className="truncate text-xl font-bold text-slate-950" id="outcome-title">
              {task.title}
            </h2>
          </div>
          <button
            aria-label="Close outcome sheet"
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-slate-100 text-xl text-slate-600 disabled:opacity-50"
            disabled={saving}
            onClick={onDismiss}
            type="button"
          >
            ×
          </button>
        </div>

        {resultNeedingReason ? (
          <div>
            <button
              className="mb-3 min-h-11 rounded-xl px-2 text-sm font-semibold text-slate-600 hover:bg-slate-100"
              disabled={saving}
              onClick={() => setResultNeedingReason(null)}
              type="button"
            >
              ← Choose another outcome
            </button>
            <h3 className="text-base font-bold text-slate-950">What was the main reason?</h3>
            <p className="mt-1 text-sm text-slate-500">One tap will save your answer.</p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              {FAILURE_REASONS.map((reason) => (
                <button
                  className="min-h-14 rounded-2xl border border-slate-200 bg-slate-50 px-3 py-2 text-left text-sm font-semibold leading-snug text-slate-800 transition hover:border-slate-400 hover:bg-white disabled:opacity-50"
                  disabled={saving}
                  key={reason.code}
                  onClick={() => onSelect(resultNeedingReason, reason.code)}
                  type="button"
                >
                  {reason.label}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {RESULT_OPTIONS.map((option) => (
              <button
                className={`min-h-24 rounded-2xl border p-4 text-left transition hover:brightness-95 disabled:opacity-50 ${option.style}`}
                disabled={saving}
                key={option.value}
                onClick={() => {
                  if (option.value === "partial" || option.value === "abandoned") {
                    setResultNeedingReason(option.value);
                    return;
                  }
                  void onSelect(option.value);
                }}
                type="button"
              >
                <span className="block text-base font-bold">{option.label}</span>
                <span className="mt-1 block text-xs leading-relaxed opacity-75">
                  {option.detail}
                </span>
              </button>
            ))}
          </div>
        )}

        {saving && (
          <p aria-live="polite" className="mt-4 text-center text-sm font-medium text-slate-500">
            Saving outcome…
          </p>
        )}
        {error && (
          <p className="mt-4 rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700" role="alert">
            {error}
          </p>
        )}
      </section>
    </div>
  );
}
