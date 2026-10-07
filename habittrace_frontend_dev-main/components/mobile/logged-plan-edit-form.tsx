"use client";

import { FormEvent, useEffect, useState } from "react";
import {
  getLatestFinishedExecution,
  reviseExecution,
  updateTask,
  type Task,
  type Execution,
} from "@/lib/api";
import { notifyDataChanged } from "@/lib/refresh";
import {
  FAILURE_REASONS,
  TASK_CATEGORIES,
  taskTimeInMinutes,
  toStoredTime,
  type FailureReasonCode,
} from "@/lib/mobile-task";
import Dialog from "@/components/ui/dialog";

type LogResult = "not_started" | "completed" | "partial" | "abandoned";

function localInputTime(value: string | null | undefined): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 16);
}

const PRESET_DURATIONS = [15, 30, 45, 60, 90] as const;

function isPresetDuration(minutes: number): boolean {
  return (PRESET_DURATIONS as readonly number[]).includes(minutes);
}

function toTimeInput(plannedStart: string): string {
  const minutes = taskTimeInMinutes(plannedStart);
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(
    minutes % 60,
  ).padStart(2, "0")}`;
}

export default function LoggedPlanEditForm({
  task,
  onDismiss,
  onSaved,
}: {
  task: Task;
  onDismiss: () => void;
  onSaved: () => void;
  onWarn?: (title: string, message: string) => void;
}) {
  const [title, setTitle] = useState(task.title);
  const [notes, setNotes] = useState(task.notes ?? "");
  const [plannedDate, setPlannedDate] = useState(task.planned_date);
  const [plannedTime, setPlannedTime] = useState(() =>
    toTimeInput(task.planned_start_time),
  );
  const [durationMinutes, setDurationMinutes] = useState(
    task.planned_duration_min,
  );
  const [customDuration, setCustomDuration] = useState(
    () => !isPresetDuration(task.planned_duration_min),
  );
  const [customMinutesText, setCustomMinutesText] = useState(() =>
    String(task.planned_duration_min),
  );
  const [result, setResult] = useState<LogResult | "">(
    task.task_status === "success" ? "completed" : "",
  );
  const [failureReason, setFailureReason] = useState<FailureReasonCode | "">(
    "",
  );
  const [execution, setExecution] = useState<Execution | null>(null);
  const [progress, setProgress] = useState("");
  const [interruptions, setInterruptions] = useState("0");
  const [actualStart, setActualStart] = useState("");
  const [actualEnd, setActualEnd] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const latest = await getLatestFinishedExecution(task.id);
        if (cancelled) return;
        setExecution(latest);
        setActualStart(localInputTime(latest?.actual_start_time));
        setActualEnd(localInputTime(latest?.actual_end_time));
        setInterruptions(String(latest?.interruption_count ?? 0));
        setProgress(latest?.completion_ratio != null ? String(Math.round(latest.completion_ratio * 100)) : "");
        if (latest?.outcome_status) {
          setResult(latest.outcome_status);
        } else if (task.task_status === "success") {
          setResult("completed");
        } else {
          setResult("");
        }
        const reason = latest?.failure_reason;
        if (
          reason &&
          FAILURE_REASONS.some((item) => item.code === reason)
        ) {
          setFailureReason(reason as FailureReasonCode);
        }
      } catch {
        if (!cancelled) {
          setError("Couldn’t load the saved outcome for this plan.");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [task.id, task.task_status]);

  function selectPreset(minutes: number) {
    setCustomDuration(false);
    setCustomMinutesText(String(minutes));
    setDurationMinutes(minutes);
  }

  function onCustomMinutesChange(value: string) {
    if (value !== "" && !/^\d{0,3}$/.test(value)) return;
    setCustomMinutesText(value);
    if (value === "") return;
    setDurationMinutes(Number(value));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (saving || loading) return;
    if (!title.trim()) {
      setError("Give your plan a name.");
      return;
    }
    const minutes = customDuration
      ? Number(customMinutesText)
      : durationMinutes;
    if (
      customDuration &&
      (customMinutesText.trim() === "" || !Number.isFinite(minutes))
    ) {
      setError("Enter how many minutes this plan should take.");
      return;
    }
    if (!Number.isFinite(minutes) || minutes < 5 || minutes > 480) {
      setError("Choose a duration between 5 and 480 minutes.");
      return;
    }
    if (!result) {
      setError("Choose the actual outcome. Older failed records do not include a completion percentage.");
      return;
    }
    if (result !== "completed" && result !== "not_started" && !failureReason) {
      setError("Choose what got in the way.");
      return;
    }
    if (!execution) {
      setError("No saved outcome was found for this plan.");
      return;
    }
    const percent = Number(progress), count = Number(interruptions);
    if (result !== "not_started" && (
      interruptions.trim() === "" || !Number.isInteger(count) || count < 0 || count > 10000
      || (result === "partial" && (progress.trim() === "" || !Number.isInteger(percent) || percent < 1 || percent > 99))
    )) {
      setError("Enter an interruption count and a partial completion percentage from 1 to 99.");
      return;
    }
    const start = new Date(actualStart), end = new Date(actualEnd);
    if (result !== "not_started" && (
      !actualStart || !actualEnd || Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())
      || end < start || end.getTime() > Date.now() + 300000
    )) {
      setError("Enter valid actual start and finish times.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const payload = {
        title: title.trim(),
        notes: notes.trim() || null,
        task_category: TASK_CATEGORIES.includes(
          task.task_category as (typeof TASK_CATEGORIES)[number],
        )
          ? task.task_category
          : "Other",
        planned_start_time: toStoredTime(plannedTime),
        planned_date: plannedDate,
        planned_duration_min: minutes,
        importance: task.importance,
        energy_level: task.energy_level,
        focus_level: task.focus_level,
        total_tasks_today: task.total_tasks_today,
      };

      await updateTask(task.id, payload);
      const taskStatus = result === "completed" ? "success" : "failed";
      await reviseExecution(execution.id, {
        task_status: taskStatus,
        outcome_status: result,
        completion_ratio: result === "completed" ? 1 : result === "partial" ? percent / 100 : 0,
        stopped_early: result === "partial" || result === "abandoned",
        failure_reason:
          result === "completed" ? undefined : failureReason || undefined,
        interruption_count: result === "not_started" ? 0 : count,
        actual_start_time: result === "not_started" ? undefined : start.toISOString(),
        actual_end_time: result === "not_started" ? undefined : end.toISOString(),
      });


      notifyDataChanged();
      onSaved();
    } catch {
      setError("Couldn’t save these changes. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog title="Edit logged plan" onClose={onDismiss} busy={saving}>
      {loading ? (
        <p role="status" className="text-sm text-slate-500">
          Loading saved outcome…
        </p>
      ) : (
        <form onSubmit={submit} className="space-y-5">
          <label className="block space-y-2 text-sm font-semibold">
            Plan name
            <input
              required
              maxLength={200}
              className="field"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
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
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="space-y-2 text-sm font-semibold">
              Date
              <input
                required
                type="date"
                className="field"
                value={plannedDate}
                onChange={(e) => setPlannedDate(e.target.value)}
              />
            </label>
            <label className="space-y-2 text-sm font-semibold">
              Start time
              <input
                required
                type="time"
                className="field"
                value={plannedTime}
                onChange={(e) => setPlannedTime(e.target.value)}
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
                  aria-pressed={!customDuration && durationMinutes === n}
                  className={
                    !customDuration && durationMinutes === n
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
                onClick={() => {
                  setCustomDuration(true);
                  setCustomMinutesText(String(durationMinutes));
                }}
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
                  className="field"
                  value={customMinutesText}
                  onChange={(e) => onCustomMinutesChange(e.target.value)}
                />
              </label>
            )}
          </fieldset>
          <fieldset>
            <legend className="mb-2 text-sm font-semibold">Log result</legend>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              {(
                [
                  {
                    value: "completed",
                    title: "Completed",
                    detail: "Finished as planned",
                  },
                  {
                    value: "partial",
                    title: "Partly completed",
                    detail: "Some progress",
                  },
                  {
                    value: "abandoned",
                    title: "Not completed",
                    detail: "Didn’t finish",
                  },
                  { value: "not_started", title: "Didn’t start", detail: "No execution time" },
                ] as const
              ).map((option) => (
                <button
                  key={option.value}
                  type="button"
                  aria-pressed={result === option.value}
                  className={`rounded-2xl border p-3 text-left ${
                    result === option.value
                      ? "border-slate-900 bg-slate-950 text-white"
                      : "border-slate-200 bg-white hover:bg-slate-50"
                  }`}
                  onClick={() => {
                    setResult(option.value);
                    if (option.value === "completed") setFailureReason("");
                  }}
                >
                  <span className="block text-sm font-semibold">
                    {option.title}
                  </span>
                  <span
                    className={`mt-1 block text-xs ${
                      result === option.value
                        ? "text-slate-300"
                        : "text-slate-500"
                    }`}
                  >
                    {option.detail}
                  </span>
                </button>
              ))}
            </div>
          </fieldset>
          {result !== "not_started" && (
            <fieldset className="space-y-3">
              <legend className="text-sm font-semibold">Actual execution</legend>
              <label className="block text-sm">Started
                <input type="datetime-local" className="field mt-1" value={actualStart}
                  onChange={(e) => setActualStart(e.target.value)} required />
              </label>
              <label className="block text-sm">Finished
                <input type="datetime-local" className="field mt-1" value={actualEnd}
                  onChange={(e) => setActualEnd(e.target.value)} required />
              </label>
              <label className="block text-sm">Times interrupted
                <input type="number" min="0" max="10000" step="1" className="field mt-1"
                  value={interruptions} onChange={(e) => setInterruptions(e.target.value)} required />
              </label>
              {result === "partial" && (
                <label className="block text-sm">Completed (%)
                  <input type="number" min="1" max="99" step="1" className="field mt-1"
                    value={progress} onChange={(e) => setProgress(e.target.value)} required />
                </label>
              )}
            </fieldset>
          )}
          {result !== "completed" && (
            <label className="block space-y-2 text-sm font-semibold">
              What got in the way?
              <select
                required={result !== "not_started"}
                className="field"
                value={failureReason}
                onChange={(e) =>
                  setFailureReason(e.target.value as FailureReasonCode | "")
                }
              >
                <option value="">{result === "not_started" ? "Optional reason" : "Select a reason"}</option>
                {FAILURE_REASONS.map((reason) => (
                  <option key={reason.code} value={reason.code}>
                    {reason.label}
                  </option>
                ))}
              </select>
            </label>
          )}
          {error && (
            <p
              role="alert"
              className="rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
            >
              {error}
            </p>
          )}
          <button
            disabled={saving || loading}
            className="btn-primary w-full"
            type="submit"
          >
            {saving ? "Saving…" : "Save changes"}
          </button>
        </form>
      )}
    </Dialog>
  );
}
