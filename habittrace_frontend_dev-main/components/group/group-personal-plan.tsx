"use client";

import { useEffect, useState } from "react";
import PlanDecisions from "@/components/plan-decisions";
import Link from "next/link";
import Dialog from "@/components/ui/dialog";
import {
  ApiError,
  acknowledgeGroupSource,
  confirmGroupPersonalPlan,
  getGroupPersonalContext,
  previewGroupPersonalPlan,
  shareGroupLinkedCompletion,
  type GroupTask,
  type Task,
  type GroupPersonalContext,
  type GroupPersonalPlanInput,
  type GroupPersonalPreview,
} from "@/lib/api";
import { describeApiError, formatDue } from "@/lib/group";
import { localDateString, createQuickAddDefaults } from "@/lib/mobile-task";
import {
  groupBlockInstant,
  groupLocalStart,
  minutesLabel,
} from "@/lib/group-planning";

const field =
  "min-h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm";
const label = "block space-y-1 text-sm font-medium text-slate-700";
const INITIAL_BLOCK = "00000000-0000-4000-8000-000000000001";

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
  const [searchDays, setSearchDays] = useState(14);
  const [requiredEnergy, setRequiredEnergy] = useState(3);
  const [requiredFocus, setRequiredFocus] = useState(3);
  const [energy, setEnergy] = useState(3);
  const [focus, setFocus] = useState(3);
  const [context, setContext] = useState<GroupPersonalContext | null>(null);
  const [decisionTask, setDecisionTask] = useState<Task | null>(null);
  const [editing, setEditing] = useState<Task | null>(null);
  const [blockKey, setBlockKey] = useState(INITIAL_BLOCK);
  const [preview, setPreview] = useState<GroupPersonalPreview | null>(null);
  const [reviewedInput, setReviewedInput] =
    useState<GroupPersonalPlanInput | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const source = context?.group_task ?? task;

  useEffect(() => {
    let cancelled = false;
    getGroupPersonalContext(task.group_id, task.id)
      .then((next) => {
        if (cancelled) return;
        setContext(next);
        if (next.blocks.length) setBlockKey(crypto.randomUUID());
        if (next.remaining_minutes)
          setDuration(Math.min(60, next.remaining_minutes));
      })
      .catch((caught) => {
        if (!cancelled)
          setError(
            describeApiError(
              caught,
              "We couldn't load your blocks. Close and retry.",
            ),
          );
      });
    return () => {
      cancelled = true;
    };
  }, [task.group_id, task.id]);

  function invalidate() {
    setPreview(null);
    setReviewedInput(null);
    setError(null);
    setMessage(null);
  }
  function newBlock() {
    invalidate();
    setEditing(null);
    setBlockKey(crypto.randomUUID());
    setDuration(
      Math.min(
        60,
        context?.remaining_minutes || source.estimated_duration_minutes || 30,
      ),
    );
  }
  function edit(block: Task) {
    try {
      const start = groupBlockInstant(block);
      setDate(localDateString(start));
      setClock(
        `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}`,
      );
      setDuration(block.planned_duration_min);
      setRequiredEnergy(block.energy_level);
      setRequiredFocus(block.focus_level);
      setEditing(block);
      invalidate();
    } catch (caught) {
      setError((caught as Error).message);
    }
  }
  function input(): GroupPersonalPlanInput {
    return {
      personal_task_id: editing?.id,
      block_key: blockKey,
      search_days: searchDays,
      expected_source_updated_at: source.updated_at,
      planned_start: groupLocalStart(date, clock),
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
    invalidate();
    try {
      const draft = override ?? input();
      const result = await previewGroupPersonalPlan(
        task.group_id,
        task.id,
        draft,
      );
      if (result.personal_task && !draft.personal_task_id) {
        setContext(await getGroupPersonalContext(task.group_id, task.id));
        setBlockKey(crypto.randomUUID());
        setMessage("This block is already saved in your plans.");
      } else {
        setPreview(result);
        setReviewedInput(draft);
      }
    } catch (caught) {
      setError(
        caught instanceof Error && caught.message.startsWith("Choose ")
          ? caught.message
          : describeApiError(
              caught,
              "We couldn't check this plan. Please retry.",
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
      // Clear the old draft immediately after a successful save; retry cannot create a duplicate.
      setPreview(null);
      setReviewedInput(null);
      setEditing(null);
      setBlockKey(crypto.randomUUID());
      setMessage(
        editing
          ? "Block updated. Your previous outcomes are preserved."
          : "Block added to your plans.",
      );
      onAdded();
      const next = await getGroupPersonalContext(task.group_id, task.id);
      setContext(next);
      setDuration(Math.min(60, next.remaining_minutes || 30));
    } catch (caught) {
      setError(
        describeApiError(
          caught,
          "We couldn't save or refresh. Review your blocks before retrying.",
        ),
      );
      if (caught instanceof ApiError && caught.status === 409) {
        setPreview(null);
        setReviewedInput(null);
        try {
          const next = await getGroupPersonalContext(task.group_id, task.id);
          setContext(next);
          if (
            editing &&
            !next.blocks.some(
              (b) =>
                b.task.id === editing.id && b.task.task_status === "pending",
            )
          )
            setEditing(null);
        } catch {
          /* Keep the conflict visible if refresh also fails. */
        }
      }
    } finally {
      setBusy(false);
    }
  }
  async function acknowledge() {
    setBusy(true);
    setError(null);
    try {
      setContext(
        await acknowledgeGroupSource(task.group_id, task.id, source.updated_at),
      );
    } catch (caught) {
      setError(describeApiError(caught, "We couldn't acknowledge the change."));
    } finally {
      setBusy(false);
    }
  }
  async function shareCompletion() {
    setBusy(true);
    setError(null);
    try {
      setContext(await shareGroupLinkedCompletion(task.group_id, task.id));
      setMessage("Your completion is now shared with the group.");
    } catch (caught) {
      setError(
        describeApiError(
          caught,
          "Your personal results are saved. Group completion could not be shared; retry here.",
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
  const changed = context?.blocks.some((b) => b.source_changed);
  if (decisionTask)
    return (
      <PlanDecisions
        task={decisionTask}
        onClose={() => setDecisionTask(null)}
        onApplied={() => {
          onAdded();
          void getGroupPersonalContext(task.group_id, task.id).then(setContext);
        }}
      />
    );
  return (
    <Dialog title="My group task plan" onClose={onClose} busy={busy}>
      <p className="font-semibold text-slate-900">{source.title}</p>
      <p className="mt-1 text-xs text-slate-500">
        {formatDue(source) ? `Due ${formatDue(source)}` : "No deadline"}
      </p>
      <p className="my-3 text-sm text-slate-500">
        Your prediction and personal schedule are visible only to you.
      </p>
      {changed && (
        <div
          role="status"
          className="mb-4 space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"
        >
          <p>
            The group deadline or estimate changed, or this older plan has not
            been reviewed. Your schedule has not moved.
          </p>
          {context?.blocks.some(
            (b) =>
              b.finishes_after_deadline && b.task.task_status === "pending",
          ) ? (
            <p>Move the highlighted blocks before the new deadline.</p>
          ) : (
            <button
              type="button"
              className="btn-secondary"
              disabled={busy}
              onClick={() => void acknowledge()}
            >
              I reviewed this change
            </button>
          )}
        </div>
      )}
      {context && context.blocks.length > 0 && (
        <section className="mb-5 space-y-3" aria-label="My work blocks">
          <p className="text-sm">
            {context.planned_minutes} min allocated ·{" "}
            {context.completed_minutes} planned min in completed blocks
            {context.partial_progress_minutes > 0 &&
              ` · ~${context.partial_progress_minutes} planned min credited from partial progress`}
            {context.remaining_minutes !== null &&
              ` · ${context.remaining_minutes} min still to allocate`}
          </p>
          <ul className="space-y-2">
            {context.blocks.map(
              ({ task: block, finishes_after_deadline, source_changed }) => (
                <li
                  key={block.id}
                  className="rounded-xl border border-slate-200 p-3 text-sm"
                >
                  <p>
                    {block.planned_date} · {block.planned_start_time} (
                    {block.timezone_name || "UTC"}) ·{" "}
                    {block.planned_duration_min} min · {block.task_status}
                  </p>
                  {block.task_status !== "success" && (
                    <button
                      type="button"
                      className="mt-2 block text-sm text-violet-700 underline"
                      onClick={() => setDecisionTask(block)}
                    >
                      Compare full alternatives / plan remaining work
                    </button>
                  )}
                  {source_changed && (
                    <p className="text-amber-800">Group details need review</p>
                  )}
                  {finishes_after_deadline && (
                    <p className="text-rose-700">
                      Finishes after the current deadline
                    </p>
                  )}
                  {block.task_status === "pending" && (
                    <button
                      type="button"
                      className="mt-2 text-violet-700 underline"
                      disabled={busy}
                      onClick={() => edit(block)}
                    >
                      Recheck prediction / move block
                    </button>
                  )}
                </li>
              ),
            )}
          </ul>
          <button
            type="button"
            className="btn-secondary"
            disabled={busy}
            onClick={newBlock}
          >
            Plan another block
          </button>
          <Link
            href="/dashboard/habits"
            className="ml-3 text-sm text-violet-700 underline"
          >
            Record work in Plans
          </Link>
          {context.can_share_completion &&
            context.shared_outcome !== "success" && (
              <div className="rounded-xl bg-emerald-50 p-3 text-sm">
                <p>
                  Your completed blocks cover the shared estimate. Mark the
                  shared task complete for you too?
                </p>
                <button
                  type="button"
                  className="btn-primary mt-2"
                  disabled={busy}
                  onClick={() => void shareCompletion()}
                >
                  Yes, share my completion
                </button>
                <p className="mt-1 text-xs">
                  Only completion is shared. Your predictions and personal
                  inputs stay private.
                </p>
              </div>
            )}
        </section>
      )}
      {message && (
        <p
          role="status"
          className="mb-3 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800"
        >
          {message}
        </p>
      )}
      {!context && !error && <p role="status">Loading your blocks…</p>}
      {context && (
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            void review();
          }}
        >
          <p className="font-medium">
            {editing ? "Review changes to this block" : "Plan a work block"}
          </p>
          <fieldset disabled={busy} className="space-y-4 disabled:opacity-60">
            <div className="grid grid-cols-1 min-[400px]:grid-cols-2 gap-3">
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
              Times use {timezone}. Each block must finish before the deadline.
            </p>
            {editing && (
              <p className="rounded-xl bg-slate-100 p-3 text-sm">
                Before: {editing.planned_date} {editing.planned_start_time} (
                {editing.timezone_name || "UTC"}),{" "}
                {editing.planned_duration_min} min. Only this pending block will
                change after confirmation.
              </p>
            )}
            <label className={label}>
              Block duration (minutes)
              <input
                className={field}
                type="number"
                value={duration}
                min={1}
                max={720}
                required
                onChange={(e) => {
                  setDuration(Number(e.target.value));
                  invalidate();
                }}
              />
            </label>
            {!editing && (
              <p className="text-xs text-slate-500">
                For a long task, plan a smaller block now and use “Plan another
                block” for the rest. Each block has its own result.
              </p>
            )}
            <label className={label}>
              Days to search from work date
              <select
                className={field}
                value={searchDays}
                onChange={(e) => {
                  setSearchDays(Number(e.target.value));
                  invalidate();
                }}
              >
                {[1, 7, 14, 31].map((days) => (
                  <option key={days} value={days}>
                    {days} {days === 1 ? "day" : "days"} (stops at deadline)
                  </option>
                ))}
              </select>
            </label>
            <div className="grid grid-cols-1 min-[400px]:grid-cols-2 gap-3">
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
            {busy ? "Checking…" : "Check prediction & available dates"}
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
              {preview.search_start && (
                <p className="text-xs text-slate-500">
                  Searched {preview.search_start}–{preview.search_end},
                  08:00–22:00. Expected energy and focus are held constant;
                  update them when choosing another day.
                </p>
              )}
              {preview.candidates.length ? (
                <div className="space-y-2">
                  <p className="text-sm font-medium">Available alternatives</p>
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
                        void review({
                          ...reviewedInput!,
                          planned_start: candidate.planned_start,
                        });
                      }}
                    >
                      <span className="block font-medium">
                        {new Date(candidate.planned_start).toLocaleString([], {
                          weekday: "short",
                          month: "short",
                          day: "numeric",
                          hour: "numeric",
                          minute: "2-digit",
                        })}
                        {candidate.success_probability !== null &&
                          ` · ${Math.round(candidate.success_probability * 100)}% estimated`}
                      </span>
                      <span className="block text-xs text-slate-500">
                        {minutesLabel(candidate.daily_planned_minutes)}{" "}
                        scheduled that day including this block
                        {candidate.deadline_slack_minutes !== null &&
                          ` · ${minutesLabel(candidate.deadline_slack_minutes)} before deadline after finishing`}
                      </span>
                    </button>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-slate-500">
                  No alternative fits this search window. Try another date or a
                  shorter block.
                </p>
              )}
              <p className="text-sm">
                After: {date} {clock} ({timezone}), {duration} min.
              </p>
              <button
                className="btn-primary w-full"
                type="button"
                disabled={
                  busy ||
                  preview.conflicts.length > 0 ||
                  (!!preview.personal_task && !editing)
                }
                onClick={() => void confirm()}
              >
                {editing
                  ? "Confirm changes to this block"
                  : preview.personal_task
                    ? "This block is already saved"
                    : "Add this block to my plans"}
              </button>
            </div>
          )}
        </form>
      )}
      {error && (
        <p
          role="alert"
          className="mt-3 rounded-xl bg-rose-50 p-3 text-sm text-rose-800"
        >
          {error}
        </p>
      )}
    </Dialog>
  );
}
