"use client";
import { useRef, useState } from "react";
import type { ExecutionCompleteInput, Task } from "@/lib/api";
import {
  FAILURE_REASONS,
  formatScheduledEnd,
  formatScheduledRange,
  type FailureReasonCode,
} from "@/lib/mobile-task";
import {
  buildOutcomeInput,
  EMPTY_OUTCOME_DRAFT,
  MAX_MINUTES_SPENT,
  type OutcomeChoice,
  type OutcomeDraft,
} from "@/lib/outcome";
import Dialog from "@/components/ui/dialog";

const CHOICES: {
  value: OutcomeChoice;
  title: string;
  detail: string;
  style: string;
}[] = [
  {
    value: "completed",
    title: "Completed",
    detail: "I finished this plan",
    style:
      "aria-checked:border-emerald-500 aria-checked:bg-emerald-50 aria-checked:ring-2 aria-checked:ring-emerald-200",
  },
  {
    value: "not_completed",
    title: "Not completed",
    detail: "I didn’t finish this plan",
    style:
      "aria-checked:border-slate-500 aria-checked:bg-slate-50 aria-checked:ring-2 aria-checked:ring-slate-200",
  },
];

/** Select Completed / Not completed, add optional details, then Submit. Nothing saves on selection. */
export default function OutcomeSheet({
  task,
  activeStart,
  error,
  saving,
  onDismiss,
  onSubmit,
}: {
  task: Task;
  /** Recorded start of a legacy timer, if this plan was started before Start was removed. */
  activeStart?: string | null;
  error: string | null;
  saving: boolean;
  onDismiss: () => void;
  onSubmit: (input: ExecutionCompleteInput) => Promise<void>;
}) {
  const [draft, setDraft] = useState<OutcomeDraft>(EMPTY_OUTCOME_DRAFT);
  const [formError, setFormError] = useState<string | null>(null);
  // Blocks a second Submit before the parent's `saving` state re-renders the form.
  const submitting = useRef(false);
  const scheduledEnd = formatScheduledEnd(
    task.planned_start_time,
    task.planned_duration_min,
  );
  const busy = saving;

  function update(changes: Partial<OutcomeDraft>) {
    setDraft((current) => ({ ...current, ...changes }));
    setFormError(null);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting.current || saving) return;
    const built = buildOutcomeInput(draft, { activeStart });
    if (!built.ok) {
      setFormError(built.error);
      return;
    }
    submitting.current = true;
    try {
      await onSubmit(built.input);
    } finally {
      submitting.current = false;
    }
  }

  return (
    <Dialog title={task.title} onClose={onDismiss} busy={saving}>
      <p className="mb-4 text-sm text-slate-500">
        Scheduled{" "}
        {formatScheduledRange(
          task.planned_start_time,
          task.planned_duration_min,
        )}
        {activeStart && (
          <>
            {" "}
            · started{" "}
            {new Date(activeStart).toLocaleTimeString("en-US", {
              hour: "numeric",
              minute: "2-digit",
            })}
          </>
        )}
      </p>
      <form onSubmit={submit} noValidate>
        <div
          role="radiogroup"
          aria-label="Outcome"
          className="grid grid-cols-2 gap-3"
        >
          {CHOICES.map((option) => (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={draft.choice === option.value}
              disabled={busy}
              onClick={() =>
                update({ choice: option.value, didNotStart: false })
              }
              className={`min-h-20 rounded-2xl border border-slate-200 p-4 text-left transition ${option.style}`}
            >
              <span className="block font-semibold">{option.title}</span>
              <span className="mt-1 block text-sm text-slate-600">
                {option.detail}
              </span>
            </button>
          ))}
        </div>

        {draft.choice === "completed" && (
          <label className="mt-5 block text-sm font-semibold">
            What time did you actually finish?{" "}
            <span className="font-normal text-slate-500">(optional)</span>
            <input
              type="datetime-local"
              className="field mt-1"
              value={draft.finishedAt}
              disabled={busy}
              onChange={(event) => update({ finishedAt: event.target.value })}
            />
            <span className="mt-1 block text-xs font-normal text-slate-500">
              {scheduledEnd
                ? `Leave blank to show the scheduled end (${scheduledEnd}). It won’t be saved as your actual finish time.`
                : "Leave blank if you don’t know."}
            </span>
          </label>
        )}

        {draft.choice === "completed" && (
          <label className="mt-4 block text-sm font-semibold">
            Minutes you actually worked{" "}
            <span className="font-normal text-slate-500">(optional)</span>
            <input
              className="field mt-1"
              type="number"
              min="0"
              max={MAX_MINUTES_SPENT}
              value={draft.minutesSpent}
              disabled={busy}
              onChange={(e) => update({ minutesSpent: e.target.value })}
            />
            <span className="mt-1 block text-xs font-normal text-slate-500">
              A reported duration helps estimate similar work. Leave blank if
              unknown.
            </span>
          </label>
        )}
        {draft.choice === "not_completed" && (
          <div className="mt-5 space-y-4">
            {!activeStart && (
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  className="h-4 w-4"
                  checked={draft.didNotStart}
                  disabled={busy}
                  onChange={(event) =>
                    update({
                      didNotStart: event.target.checked,
                      minutesSpent: "",
                    })
                  }
                />
                I didn’t start this task
              </label>
            )}
            {!draft.didNotStart && (
              <label className="block text-sm font-semibold">
                How many minutes did you spend on this task?{" "}
                <span className="font-normal text-slate-500">(optional)</span>
                <input
                  type="number"
                  min="0"
                  max={MAX_MINUTES_SPENT}
                  step="1"
                  inputMode="numeric"
                  className="field mt-1"
                  value={draft.minutesSpent}
                  disabled={busy}
                  onChange={(event) =>
                    update({ minutesSpent: event.target.value })
                  }
                />
                <span className="mt-1 block text-xs font-normal text-slate-500">
                  Leave blank if you’re not sure; it stays unrecorded.
                </span>
              </label>
            )}
            {!draft.didNotStart && (
              <label className="block text-sm font-semibold">
                How much of the work is done?{" "}
                <span className="font-normal text-slate-500">(optional)</span>
                <input
                  className="field mt-1"
                  type="number"
                  min="0"
                  max="99"
                  placeholder="Progress in %"
                  value={draft.progressPercent ?? ""}
                  disabled={busy}
                  onChange={(e) => update({ progressPercent: e.target.value })}
                />
                <span className="mt-1 block text-xs font-normal text-slate-500">
                  For example, 50% records a partial result. You can plan the
                  remaining work from Plans.
                </span>
              </label>
            )}
            <label className="block text-sm font-semibold">
              What got in the way?{" "}
              <span className="font-normal text-slate-500">(optional)</span>
              <select
                className="field mt-1"
                value={draft.reason}
                disabled={busy}
                onChange={(event) =>
                  update({
                    reason: event.target.value as FailureReasonCode | "",
                  })
                }
              >
                <option value="">Prefer not to say</option>
                {FAILURE_REASONS.map((reason) => (
                  <option key={reason.code} value={reason.code}>
                    {reason.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
        )}

        {draft.choice && !draft.didNotStart && !activeStart && (
          <details className="mt-4 rounded-xl border border-slate-200 p-3">
            <summary className="cursor-pointer text-sm font-medium">
              Record my actual start time (optional)
            </summary>
            <label className="mt-3 block text-sm">
              When did you start?
              <input
                className="field mt-1"
                type="datetime-local"
                value={draft.actualStartAt ?? ""}
                disabled={busy}
                onChange={(e) => update({ actualStartAt: e.target.value })}
              />
            </label>
            <p className="mt-1 text-xs text-slate-500">
              Leave blank if unknown. A known start helps compare estimates made
              before your work.
            </p>
          </details>
        )}
        {(formError || error) && (
          <p
            role="alert"
            className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
          >
            {formError ?? error}
          </p>
        )}

        <button
          type="submit"
          className="btn-primary mt-5 w-full disabled:opacity-60"
          disabled={!draft.choice || busy}
        >
          {saving ? "Saving…" : "Submit"}
        </button>
      </form>
    </Dialog>
  );
}
