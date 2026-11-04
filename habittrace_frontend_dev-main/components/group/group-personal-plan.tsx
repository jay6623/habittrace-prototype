"use client";

import { useState } from "react";
import Link from "next/link";
import Dialog from "@/components/ui/dialog";
import {
  confirmGroupPersonalPlan,
  previewGroupPersonalPlan,
  type GroupTask,
  type GroupPersonalPlanInput,
  type GroupPersonalPreview,
} from "@/lib/api";
import { describeApiError } from "@/lib/group";
import { localDateString, createQuickAddDefaults } from "@/lib/mobile-task";

const field =
  "min-h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm";
const label = "block space-y-1 text-sm font-medium text-slate-700";

export default function GroupPersonalPlan({
  task,
  onClose,
  onAdded,
}: {
  task: GroupTask;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [defaults] = useState(createQuickAddDefaults);
  const [date, setDate] = useState(defaults.plannedDate);
  const [clock, setClock] = useState(defaults.plannedTime);
  const [duration, setDuration] = useState(
    task.estimated_duration_minutes ?? 30,
  );
  const [requiredEnergy, setRequiredEnergy] = useState(3);
  const [requiredFocus, setRequiredFocus] = useState(3);
  const [energy, setEnergy] = useState(3);
  const [focus, setFocus] = useState(3);
  const [preview, setPreview] = useState<GroupPersonalPreview | null>(null);
  const [reviewedInput, setReviewedInput] =
    useState<GroupPersonalPlanInput | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [added, setAdded] = useState(false);
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

  function invalidate() {
    setPreview(null);
    setReviewedInput(null);
    setError(null);
  }

  function input(): GroupPersonalPlanInput {
    const start = new Date(`${date}T${clock}:00`);
    // Reject nonexistent local clock times during daylight-saving transitions.
    if (
      !Number.isFinite(start.getTime()) ||
      localDateString(start) !== date ||
      `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}` !==
        clock
    ) {
      throw new Error("Choose a valid local date and time.");
    }
    const nextHour = new Date(start.getTime() + 60 * 60 * 1000);
    const previousHour = new Date(start.getTime() - 60 * 60 * 1000);
    if (
      [nextHour, previousHour].some(
        (other) =>
          other.getHours() === start.getHours() &&
          other.getMinutes() === start.getMinutes() &&
          localDateString(other) === date,
      )
    ) {
      throw new Error(
        "Choose a time outside the repeated daylight-saving hour.",
      );
    }
    return {
      planned_start: start.toISOString(),
      planned_duration_minutes: duration,
      timezone_name: timezone,
      required_energy: requiredEnergy,
      required_focus: requiredFocus,
      current_energy: energy,
      current_focus: focus,
    };
  }

  async function review(override?: GroupPersonalPlanInput) {
    setBusy(true);
    setError(null);
    setPreview(null);
    setReviewedInput(null);
    try {
      const draft = override ?? input();
      const result = await previewGroupPersonalPlan(
        task.group_id,
        task.id,
        draft,
      );
      setPreview(result);
      setReviewedInput(draft);
    } catch (caught) {
      setError(
        caught instanceof Error && caught.message.startsWith("Choose ")
          ? caught.message
          : describeApiError(
              caught,
              "We couldn't check this plan. Please try again.",
            ),
      );
    } finally {
      setBusy(false);
    }
  }

  async function confirm() {
    if (!reviewedInput) return;
    setBusy(true);
    setError(null);
    try {
      await confirmGroupPersonalPlan(task.group_id, task.id, reviewedInput);
      setAdded(true);
      onAdded();
    } catch (caught) {
      setError(
        describeApiError(
          caught,
          "We couldn't add this plan. Please review the time and retry.",
        ),
      );
    } finally {
      setBusy(false);
    }
  }

  const levels = [
    {
      name: "Task energy needed",
      value: requiredEnergy,
      change: setRequiredEnergy,
    },
    {
      name: "Task focus needed",
      value: requiredFocus,
      change: setRequiredFocus,
    },
    { name: "My expected energy", value: energy, change: setEnergy },
    { name: "My expected focus", value: focus, change: setFocus },
  ];

  return (
    <Dialog title="My group task plan" onClose={onClose} busy={busy}>
      <p className="mb-2 font-semibold text-slate-900">{task.title}</p>
      <p className="mb-4 text-sm text-slate-500">
        Your prediction and personal schedule are visible only to you.
      </p>
      {added || preview?.personal_task ? (
        <div className="space-y-4">
          <p
            role="status"
            className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"
          >
            {added
              ? "Added to your plans."
              : "This task is already in your personal plans."}
          </p>
          <p className="text-sm text-slate-600">
            Track your work in Plans. Log your shared completion separately in
            Groups.
          </p>
          <Link href="/dashboard/habits" className="btn-primary inline-block">
            Open my plans
          </Link>
        </div>
      ) : (
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            void review();
          }}
        >
          <fieldset disabled={busy} className="space-y-4 disabled:opacity-60">
            <div className="grid grid-cols-2 gap-3">
              <label className={label}>
                Work date
                <input
                  className={field}
                  type="date"
                  value={date}
                  required
                  min={localDateString()}
                  onChange={(e) => {
                    setDate(e.target.value);
                    invalidate();
                  }}
                />
              </label>
              <label className={label}>
                Start time
                <input
                  className={field}
                  type="time"
                  value={clock}
                  required
                  onChange={(e) => {
                    setClock(e.target.value);
                    invalidate();
                  }}
                />
              </label>
            </div>
            <p className="text-xs text-slate-500">
              Times use {timezone}. Finish your work before the group deadline.
            </p>
            <label className={label}>
              Duration (minutes)
              <input
                className={field}
                type="number"
                value={duration}
                required
                min={1}
                max={720}
                onChange={(e) => {
                  setDuration(Number(e.target.value));
                  invalidate();
                }}
              />
            </label>
            <div className="grid grid-cols-2 gap-3">
              {levels.map((level) => (
                <label className={label} key={level.name}>
                  {level.name}
                  <select
                    className={field}
                    value={level.value}
                    onChange={(e) => {
                      level.change(Number(e.target.value));
                      invalidate();
                    }}
                  >
                    {[1, 2, 3, 4, 5].map((n) => (
                      <option key={n} value={n}>
                        {n} — {n === 1 ? "Low" : n === 5 ? "High" : "Moderate"}
                      </option>
                    ))}
                  </select>
                </label>
              ))}
            </div>
          </fieldset>
          <button className="btn-secondary" type="submit" disabled={busy}>
            {busy ? "Checking…" : "Check my prediction"}
          </button>
          {preview && (
            <div className="space-y-3" aria-live="polite">
              {preview.prediction && (
                <div className="rounded-xl bg-violet-50 p-4 text-sm">
                  <p className="font-semibold text-violet-900">
                    {Math.round(preview.prediction.success_probability * 100)}%
                    estimated success
                  </p>
                  <p className="mt-1 text-xs text-slate-600">
                    {preview.prediction.personalization.applied
                      ? `Adjusted using ${preview.prediction.personalization.sample_count} of your recorded outcomes.`
                      : "Shared model estimate; limited personal history."}{" "}
                    Experimental guidance; not a validated personal success
                    probability.
                  </p>
                  {preview.prediction.predicted_failure_reason && (
                    <p className="mt-2">
                      Possible risk:{" "}
                      {preview.prediction.predicted_failure_reason.replaceAll(
                        "_",
                        " ",
                      )}
                    </p>
                  )}
                  {preview.prediction.recommended_actions.map((action) => (
                    <p className="mt-2" key={action.code}>
                      <span className="font-medium">{action.title}: </span>
                      {action.detail}
                    </p>
                  ))}
                </div>
              )}
              {preview.conflicts.length > 0 && (
                <p
                  role="alert"
                  className="rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
                >
                  Overlaps: {preview.conflicts.join(", ")}. Choose another time.
                </p>
              )}
              {preview.warnings.map((warning) => (
                <p className="text-sm text-amber-800" key={warning}>
                  {warning}
                </p>
              ))}
              {preview.candidates.length > 0 && (
                <div className="space-y-2">
                  <p className="text-sm font-medium">
                    Other available times on this day
                  </p>
                  {preview.candidates.map((candidate) => (
                    <button
                      key={candidate.planned_start}
                      className="block w-full rounded-xl border border-slate-200 p-3 text-left text-sm hover:bg-slate-50"
                      type="button"
                      disabled={busy}
                      onClick={() => {
                        const start = new Date(candidate.planned_start);
                        setDate(localDateString(start));
                        setClock(
                          `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}`,
                        );
                        setPreview(null);
                        void review({
                          ...reviewedInput!,
                          planned_start: candidate.planned_start,
                        });
                      }}
                    >
                      {new Date(candidate.planned_start).toLocaleTimeString(
                        [],
                        { hour: "numeric", minute: "2-digit" },
                      )}
                      {" · "}
                      {Math.round(candidate.success_probability * 100)}%
                      estimated
                    </button>
                  ))}
                </div>
              )}
              <button
                className="btn-primary w-full"
                type="button"
                disabled={busy || preview.conflicts.length > 0}
                onClick={() => void confirm()}
              >
                Add to my plans
              </button>
              <p className="text-xs text-slate-500">
                Group completion is recorded separately. Your personal plan
                stays in your history if the group task is removed.
              </p>
            </div>
          )}
          {error && (
            <p
              role="alert"
              className="rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
            >
              {error}
            </p>
          )}
        </form>
      )}
    </Dialog>
  );
}
