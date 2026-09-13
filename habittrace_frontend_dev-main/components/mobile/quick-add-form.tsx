"use client";
import { FormEvent, useState } from "react";
import { useAuth } from "@/app/providers";
import { getTasks, type Task } from "@/lib/api";
import { readPreferences } from "@/lib/preferences";
import {
  TASK_CATEGORIES,
  createQuickAddDefaults,
  formatTaskTime,
  type QuickAddDraft,
} from "@/lib/mobile-task";
import { findOverlappingTasks } from "@/lib/scheduling";
import Dialog from "@/components/ui/dialog";

const PRESET_DURATIONS = [15, 30, 45, 60, 90] as const;

function isPresetDuration(minutes: number): boolean {
  return (PRESET_DURATIONS as readonly number[]).includes(minutes);
}

function resolveDraft(
  draft: QuickAddDraft,
  customDuration: boolean,
  customMinutesText: string,
): QuickAddDraft | { error: string } {
  if (!draft.title.trim()) return { error: "Give your plan a name." };
  const durationMinutes = customDuration
    ? Number(customMinutesText)
    : draft.durationMinutes;
  if (
    customDuration &&
    (customMinutesText.trim() === "" || !Number.isFinite(durationMinutes))
  ) {
    return { error: "Enter how many minutes this plan should take." };
  }
  if (
    !Number.isFinite(durationMinutes) ||
    durationMinutes < 5 ||
    durationMinutes > 480
  ) {
    return { error: "Choose a duration between 5 and 480 minutes." };
  }
  return {
    ...draft,
    title: draft.title.trim(),
    durationMinutes,
  };
}

export default function QuickAddForm({
  initialDate,
  initialDraft,
  excludeTaskId,
  onDismiss,
  onSubmit,
}: {
  initialDate?: string;
  initialDraft?: QuickAddDraft;
  excludeTaskId?: string;
  onDismiss: () => void;
  onSubmit: (draft: QuickAddDraft) => Promise<void>;
}) {
  const { user } = useAuth();
  const [draft, setDraft] = useState<QuickAddDraft>(() => {
    if (initialDraft) {
      return { ...initialDraft, notes: initialDraft.notes ?? "" };
    }
    return {
      title: "",
      notes: "",
      ...createQuickAddDefaults(),
      ...(initialDate ? { plannedDate: initialDate } : {}),
      durationMinutes: readPreferences(user?.user_metadata).defaultDuration,
      category: "Other",
      importance: 3,
    };
  });
  const [customDuration, setCustomDuration] = useState(
    () => !isPresetDuration(draft.durationMinutes),
  );
  const [customMinutesText, setCustomMinutesText] = useState(() =>
    String(draft.durationMinutes),
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pendingDraft, setPendingDraft] = useState<QuickAddDraft | null>(null);
  const [overlaps, setOverlaps] = useState<Task[] | null>(null);

  const confirmingOverlap = Boolean(overlaps && pendingDraft);

  function update<K extends keyof QuickAddDraft>(
    key: K,
    value: QuickAddDraft[K],
  ) {
    setDraft((d) => ({ ...d, [key]: value }));
  }

  function selectPreset(minutes: number) {
    setCustomDuration(false);
    setCustomMinutesText(String(minutes));
    update("durationMinutes", minutes);
  }

  function selectCustom() {
    setCustomDuration(true);
    setCustomMinutesText(String(draft.durationMinutes));
  }

  function onCustomMinutesChange(value: string) {
    if (value !== "" && !/^\d{0,3}$/.test(value)) return;
    setCustomMinutesText(value);
    if (value === "") return;
    update("durationMinutes", Number(value));
  }

  async function saveDraft(next: QuickAddDraft) {
    setSaving(true);
    setError(null);
    try {
      await onSubmit(next);
    } catch {
      setPendingDraft(null);
      setOverlaps(null);
      setError(
        "Your plan wasn’t saved. Your changes are still here — please try again.",
      );
    } finally {
      setSaving(false);
    }
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (saving) return;
    const resolved = resolveDraft(draft, customDuration, customMinutesText);
    if ("error" in resolved) {
      setError(resolved.error);
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const dayTasks = await getTasks(resolved.plannedDate);
      const conflicts = findOverlappingTasks(
        resolved,
        dayTasks,
        excludeTaskId,
      );
      if (conflicts.length > 0) {
        setPendingDraft(resolved);
        setOverlaps(conflicts);
        return;
      }
      await onSubmit(resolved);
    } catch {
      setError(
        "Your plan wasn’t saved. Your changes are still here — please try again.",
      );
    } finally {
      setSaving(false);
    }
  }

  function cancelOverlap() {
    setPendingDraft(null);
    setOverlaps(null);
  }

  return (
    <Dialog
      title={
        confirmingOverlap
          ? "Plans overlap"
          : initialDraft
            ? "Edit plan"
            : "What would you like to do?"
      }
      onClose={onDismiss}
      busy={saving}
    >
      {confirmingOverlap && pendingDraft && overlaps ? (
        <div className="space-y-5">
          <p className="text-sm leading-relaxed text-slate-600">
            This plan overlaps with{" "}
            {overlaps.length === 1 ? "another plan" : "other plans"} on your
            schedule. Save it anyway, or cancel to adjust the time.
          </p>
          <ul className="space-y-2 rounded-2xl bg-amber-50 p-4 text-sm text-amber-950">
            {overlaps.map((task) => (
              <li key={task.id}>
                <span className="font-semibold">{task.title}</span>
                <span className="text-amber-800">
                  {" "}
                  · {formatTaskTime(task.planned_start_time)} ·{" "}
                  {task.planned_duration_min} min
                </span>
              </li>
            ))}
          </ul>
          <div className="flex flex-col gap-3 sm:flex-row-reverse">
            <button
              type="button"
              disabled={saving}
              className="btn-primary flex-1"
              onClick={() => void saveDraft(pendingDraft)}
            >
              {saving ? "Saving…" : "Save anyway"}
            </button>
            <button
              type="button"
              disabled={saving}
              className="btn-secondary flex-1"
              onClick={cancelOverlap}
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
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
        <label className="block space-y-2 text-sm font-semibold">
          Note
          <span className="font-normal text-slate-500"> (optional)</span>
          <textarea
            maxLength={2000}
            rows={2}
            className="field min-h-[4.5rem] resize-y"
            placeholder="Add a short note…"
            value={draft.notes}
            onChange={(e) => update("notes", e.target.value)}
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
              {PRESET_DURATIONS.map((n) => (
                <button
                  key={n}
                  type="button"
                  aria-pressed={!customDuration && draft.durationMinutes === n}
                  className={
                    !customDuration && draft.durationMinutes === n
                      ? "btn-primary"
                      : "btn-secondary"
                  }
                  onClick={() => selectPreset(n)}
                >
                  {n}m
                </button>
              ))}
              <button
                type="button"
                aria-pressed={customDuration}
                className={customDuration ? "btn-primary" : "btn-secondary"}
                onClick={selectCustom}
              >
                Custom
              </button>
            </div>
            {customDuration && (
              <label className="mt-3 block space-y-2 text-sm font-semibold">
                Minutes
                <input
                  required
                  inputMode="numeric"
                  pattern="[0-9]*"
                  min={5}
                  max={480}
                  className="field"
                  placeholder="e.g. 25"
                  value={customMinutesText}
                  onChange={(e) => onCustomMinutesChange(e.target.value)}
                />
              </label>
            )}
          </fieldset>
          <div className="grid grid-cols-2 gap-3">
            <label className="space-y-2 text-sm font-semibold">
              Category
              <select
                className="field"
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
            <label className="space-y-2 text-sm font-semibold">
              Priority
              <select
                className="field"
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
          {error && (
            <p
              role="alert"
              className="rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
            >
              {error}
            </p>
          )}
          <button disabled={saving} className="btn-primary w-full" type="submit">
            {saving ? "Checking…" : "Save plan"}
          </button>
        </form>
      )}
    </Dialog>
  );
}
