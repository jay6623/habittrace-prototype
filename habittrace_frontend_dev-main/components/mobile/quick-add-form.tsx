"use client";
import { FormEvent, useState } from "react";
import { useAuth } from "@/app/providers";
import { readPreferences } from "@/lib/preferences";
import {
  TASK_CATEGORIES,
  createQuickAddDefaults,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import Dialog from "@/components/ui/dialog";

export default function QuickAddForm({
  initialDate,
  initialDraft,
  onDismiss,
  onSubmit,
}: {
  initialDate?: string;
  initialDraft?: QuickAddDraft;
  onDismiss: () => void;
  onSubmit: (draft: QuickAddDraft) => Promise<void>;
}) {
  const { user } = useAuth();
  const [draft, setDraft] = useState<QuickAddDraft>(
    () =>
      initialDraft ?? {
        title: "",
        ...createQuickAddDefaults(),
        ...(initialDate ? { plannedDate: initialDate } : {}),
        durationMinutes: readPreferences(user?.user_metadata).defaultDuration,
        category: "Other",
        importance: 3,
      },
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  function update<K extends keyof QuickAddDraft>(
    key: K,
    value: QuickAddDraft[K],
  ) {
    setDraft((d) => ({ ...d, [key]: value }));
  }
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (saving) return;
    if (!draft.title.trim()) {
      setError("Give your plan a name.");
      return;
    }
    if (
      !Number.isFinite(draft.durationMinutes) ||
      draft.durationMinutes < 5 ||
      draft.durationMinutes > 480
    ) {
      setError("Choose a duration between 5 and 480 minutes.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await onSubmit({ ...draft, title: draft.title.trim() });
    } catch {
      setError(
        "Your plan wasn’t saved. Your changes are still here — please try again.",
      );
    } finally {
      setSaving(false);
    }
  }
  return (
    <Dialog
      title={initialDraft ? "Edit plan" : "What would you like to do?"}
      onClose={onDismiss}
      busy={saving}
    >
      <form onSubmit={submit} className="space-y-5">
        <label className="block space-y-2 text-sm font-semibold">
          Plan name
          <input
            autoFocus
            required
            maxLength={200}
            className="field"
            placeholder="e.g. Read one chapter"
            value={draft.title}
            onChange={(e) => update("title", e.target.value)}
          />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="space-y-2 text-sm font-semibold">
            Date
            <input
              required
              type="date"
              className="field"
              value={draft.plannedDate}
              onChange={(e) => update("plannedDate", e.target.value)}
            />
          </label>
          <label className="space-y-2 text-sm font-semibold">
            Start time
            <input
              required
              type="time"
              className="field"
              value={draft.plannedTime}
              onChange={(e) => update("plannedTime", e.target.value)}
            />
          </label>
        </div>
        <fieldset>
          <legend className="mb-2 text-sm font-semibold">How long?</legend>
          <div className="flex flex-wrap gap-2">
            {[15, 30, 45, 60, 90].map((n) => (
              <button
                key={n}
                type="button"
                aria-pressed={draft.durationMinutes === n}
                className={
                  draft.durationMinutes === n ? "btn-primary" : "btn-secondary"
                }
                onClick={() => update("durationMinutes", n)}
              >
                {n}m
              </button>
            ))}
          </div>
        </fieldset>
        <details className="rounded-xl border border-slate-200 p-4">
          <summary className="text-sm font-semibold">More options</summary>
          <div className="mt-4 space-y-4">
            <label className="block text-sm">
              Custom duration (minutes)
              <input
                required
                type="number"
                min={5}
                max={480}
                className="field mt-2"
                value={draft.durationMinutes}
                onChange={(e) =>
                  update("durationMinutes", Number(e.target.value))
                }
              />
            </label>
            <label className="block text-sm">
              Category
              <select
                className="field mt-2"
                value={draft.category}
                onChange={(e) =>
                  update(
                    "category",
                    e.target.value as QuickAddDraft["category"],
                  )
                }
              >
                {TASK_CATEGORIES.map((c) => (
                  <option key={c}>{c}</option>
                ))}
              </select>
            </label>
            <label className="block text-sm">
              Priority
              <select
                className="field mt-2"
                value={draft.importance}
                onChange={(e) => update("importance", Number(e.target.value))}
              >
                {[1, 2, 3, 4, 5].map((n) => (
                  <option key={n} value={n}>
                    {n === 1 ? "1 — Low" : n === 5 ? "5 — High" : n}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </details>
        {error && (
          <p
            role="alert"
            className="rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
          >
            {error}
          </p>
        )}
        <button disabled={saving} className="btn-primary w-full" type="submit">
          {saving ? "Saving…" : "Save plan"}
        </button>
      </form>
    </Dialog>
  );
}
