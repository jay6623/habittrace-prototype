"use client";

import { FormEvent, useEffect, useState } from "react";
import {
  TASK_CATEGORIES,
  createQuickAddDefaults,
  type QuickAddDraft,
  type TaskCategory,
} from "@/lib/mobile-task";

const DURATION_OPTIONS = [15, 30, 45, 60, 90] as const;

const CATEGORY_LABELS: Record<TaskCategory, string> = {
  Study: "Study",
  Work: "Work",
  Chores: "Chores",
  "Fitness/Health": "Fitness & Health",
  "Errands/Admin": "Errands & Admin",
  "Hobbies/Leisure": "Hobbies & Leisure",
  Social: "Social",
  Other: "Other",
};

function initialDraft(initialDate?: string): QuickAddDraft {
  const defaults = createQuickAddDefaults();
  return {
    title: "",
    ...defaults,
    plannedDate: initialDate ?? defaults.plannedDate,
    durationMinutes: 30,
    category: "Other",
    importance: 3,
  };
}

interface QuickAddFormProps {
  initialDate?: string;
  onDismiss: () => void;
  onSubmit: (draft: QuickAddDraft) => Promise<void>;
}

export default function QuickAddForm({
  initialDate,
  onDismiss,
  onSubmit,
}: QuickAddFormProps) {
  const [draft, setDraft] = useState<QuickAddDraft>(() => initialDraft(initialDate));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !saving) onDismiss();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onDismiss, saving]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft.title.trim()) {
      setError("Enter a plan name.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      await onSubmit({ ...draft, title: draft.title.trim() });
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "We couldn't save the plan. Try again.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/45 px-0 sm:px-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !saving) onDismiss();
      }}
    >
      <section
        aria-labelledby="quick-add-title"
        aria-modal="true"
        className="max-h-[94dvh] w-full max-w-lg overflow-y-auto rounded-t-3xl bg-white shadow-2xl sm:mb-4 sm:rounded-3xl"
        role="dialog"
      >
        <form onSubmit={handleSubmit}>
          <div className="sticky top-0 z-10 flex items-center justify-between border-b border-slate-100 bg-white/95 px-5 py-4 backdrop-blur">
            <div>
              <p className="text-xs font-semibold text-emerald-700">QUICK ADD</p>
              <h2 id="quick-add-title" className="text-xl font-bold text-slate-950">
                New plan
              </h2>
            </div>
            <button
              aria-label="Close quick add"
              className="grid h-11 w-11 place-items-center rounded-full bg-slate-100 text-xl text-slate-600 transition hover:bg-slate-200 disabled:opacity-50"
              disabled={saving}
              onClick={onDismiss}
              type="button"
            >
              ×
            </button>
          </div>

          <div className="space-y-5 px-5 py-5">
            <div>
              <label className="mb-2 block text-sm font-semibold text-slate-800" htmlFor="quick-title">
                What do you want to do?
              </label>
              <input
                autoFocus
                className="min-h-12 w-full rounded-2xl border border-slate-200 bg-slate-50 px-4 text-base text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100"
                id="quick-title"
                maxLength={200}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, title: event.target.value }))
                }
                placeholder="e.g. Draft the project report"
                value={draft.title}
              />
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="mb-2 block text-sm font-semibold text-slate-800" htmlFor="quick-date">
                  Date
                </label>
                <input
                  className="min-h-12 w-full min-w-0 rounded-2xl border border-slate-200 bg-slate-50 px-3 text-base outline-none focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100"
                  id="quick-date"
                  onChange={(event) =>
                    setDraft((current) => ({
                      ...current,
                      plannedDate: event.target.value,
                    }))
                  }
                  required
                  type="date"
                  value={draft.plannedDate}
                />
              </div>
              <div>
                <label className="mb-2 block text-sm font-semibold text-slate-800" htmlFor="quick-time">
                  Start time
                </label>
                <input
                  className="min-h-12 w-full min-w-0 rounded-2xl border border-slate-200 bg-slate-50 px-3 text-base outline-none focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100"
                  id="quick-time"
                  onChange={(event) =>
                    setDraft((current) => ({
                      ...current,
                      plannedTime: event.target.value,
                    }))
                  }
                  required
                  step={300}
                  type="time"
                  value={draft.plannedTime}
                />
              </div>
            </div>

            <fieldset>
              <legend className="mb-2 text-sm font-semibold text-slate-800">
                Estimated duration
              </legend>
              <div className="grid grid-cols-5 gap-2">
                {DURATION_OPTIONS.map((duration) => (
                  <button
                    aria-pressed={draft.durationMinutes === duration}
                    className={`min-h-12 rounded-xl px-1 text-sm font-semibold transition ${
                      draft.durationMinutes === duration
                        ? "bg-slate-900 text-white"
                        : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                    }`}
                    key={duration}
                    onClick={() =>
                      setDraft((current) => ({
                        ...current,
                        durationMinutes: duration,
                      }))
                    }
                    type="button"
                  >
                    {duration}m
                  </button>
                ))}
              </div>
            </fieldset>

            <details className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
              <summary className="min-h-8 cursor-pointer text-sm font-semibold text-slate-700">
                More options
              </summary>
              <div className="mt-4 space-y-5 border-t border-slate-200 pt-4">
                <fieldset>
                  <legend className="mb-2 text-xs font-semibold text-slate-600">Category</legend>
                  <div className="flex flex-wrap gap-2">
                    {TASK_CATEGORIES.map((category) => (
                      <button
                        aria-pressed={draft.category === category}
                        className={`min-h-11 rounded-xl px-3 text-sm font-medium transition ${
                          draft.category === category
                            ? "bg-slate-900 text-white"
                            : "border border-slate-200 bg-white text-slate-700"
                        }`}
                        key={category}
                        onClick={() =>
                          setDraft((current) => ({ ...current, category }))
                        }
                        type="button"
                      >
                        {CATEGORY_LABELS[category]}
                      </button>
                    ))}
                  </div>
                </fieldset>

                <fieldset>
                  <legend className="mb-2 text-xs font-semibold text-slate-600">Priority</legend>
                  <div className="grid grid-cols-3 gap-2">
                    {[
                      { value: 2, label: "Low" },
                      { value: 3, label: "Medium" },
                      { value: 5, label: "High" },
                    ].map((option) => (
                      <button
                        aria-pressed={draft.importance === option.value}
                        className={`min-h-11 rounded-xl text-sm font-semibold ${
                          draft.importance === option.value
                            ? "bg-slate-900 text-white"
                            : "border border-slate-200 bg-white text-slate-700"
                        }`}
                        key={option.value}
                        onClick={() =>
                          setDraft((current) => ({
                            ...current,
                            importance: option.value,
                          }))
                        }
                        type="button"
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                </fieldset>
              </div>
            </details>

            {error && (
              <p className="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700" role="alert">
                {error}
              </p>
            )}
          </div>

          <div className="sticky bottom-0 border-t border-slate-100 bg-white px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4">
            <button
              className="min-h-14 w-full rounded-2xl bg-slate-950 px-5 text-base font-bold text-white shadow-lg shadow-slate-300 transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
              disabled={saving}
              type="submit"
            >
              {saving ? "Saving…" : "Save plan"}
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}
