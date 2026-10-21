/**
 * Log Outcome: two choices, optional details, explicit Submit. Pure functions only.
 *
 * Unknown values are sent as null/absent and never filled from the schedule:
 * - Completed + finish time  -> actual_end_time only (user-reported, no start)
 * - Completed + blank        -> no actual times; the UI shows the scheduled end
 * - Not completed + minutes  -> active_minutes only (no start/end)
 * - Not completed + blank    -> abandoned with unknown duration (not "not_started")
 * - Not completed + "I didn't start this task" -> not_started (explicit, confirmed)
 * Interruptions are not asked, so interruption_count is null (unknown), never 0.
 * A plan started with the legacy timer keeps its recorded start; its finish is the
 * reported time or unknown, never the moment Submit was pressed.
 */
import type { Execution, ExecutionCompleteInput, MobileOutcomeStatus } from "./api";
import type { FailureReasonCode } from "./mobile-task";

export type OutcomeChoice = "completed" | "not_completed";

export interface OutcomeDraft {
  choice: OutcomeChoice | null;
  /** `datetime-local` value in the user's timezone, or "". */
  finishedAt: string;
  minutesSpent: string;
  reason: FailureReasonCode | "";
  /** Optional under Not completed: the user confirms they never started. */
  didNotStart: boolean;
}

export const EMPTY_OUTCOME_DRAFT: OutcomeDraft = {
  choice: null,
  finishedAt: "",
  minutesSpent: "",
  reason: "",
  didNotStart: false,
};

export const MAX_MINUTES_SPENT = 1440;
const FUTURE_TOLERANCE_MS = 5 * 60_000;

export type OutcomeBuild =
  | { ok: true; input: ExecutionCompleteInput }
  | { ok: false; error: string };

export function buildOutcomeInput(
  draft: OutcomeDraft,
  { activeStart = null, now = new Date() }: { activeStart?: string | null; now?: Date } = {},
): OutcomeBuild {
  if (!draft.choice) return { ok: false, error: "Choose Completed or Not completed." };

  if (draft.choice === "completed") {
    const input: ExecutionCompleteInput = {
      task_status: "success",
      outcome_status: "completed",
      completion_ratio: 1,
      interruption_count: null,
      stopped_early: false,
    };
    if (!draft.finishedAt.trim()) return { ok: true, input: { ...input, actual_end_unknown: true } };
    const finished = new Date(draft.finishedAt);
    if (Number.isNaN(finished.getTime())) return { ok: false, error: "Enter a valid finish time." };
    if (finished.getTime() > now.getTime() + FUTURE_TOLERANCE_MS) {
      return { ok: false, error: "The finish time can’t be in the future." };
    }
    if (activeStart && finished.getTime() < new Date(activeStart).getTime()) {
      return { ok: false, error: "The finish time can’t be before you started." };
    }
    return { ok: true, input: { ...input, actual_end_time: finished.toISOString() } };
  }

  if (draft.didNotStart) {
    if (activeStart) {
      return { ok: false, error: "This plan has a recorded start, so it can’t be marked as not started." };
    }
    return {
      ok: true,
      input: {
        task_status: "failed",
        outcome_status: "not_started",
        completion_ratio: 0,
        interruption_count: 0, // nothing was executed, so zero is confirmed
        stopped_early: false,
        failure_reason: draft.reason || undefined,
      },
    };
  }

  const text = draft.minutesSpent.trim();
  const minutes = text === "" ? null : Number(text);
  if (minutes !== null && (!Number.isInteger(minutes) || minutes < 0 || minutes > MAX_MINUTES_SPENT)) {
    return { ok: false, error: `Minutes spent must be a whole number from 0 to ${MAX_MINUTES_SPENT}.` };
  }
  return {
    ok: true,
    input: {
      task_status: "failed",
      outcome_status: "abandoned",
      completion_ratio: 0,
      interruption_count: null,
      // Only a reported amount of work implies the plan was stopped before finishing.
      stopped_early: minutes !== null && minutes > 0,
      active_minutes: minutes,
      failure_reason: draft.reason || undefined,
      actual_end_unknown: true,
    },
  };
}

/** Confirmation copy; a blank finish shows the scheduled end, labelled as scheduled. */
export function outcomeConfirmation(
  input: ExecutionCompleteInput,
  scheduledEnd: string | null,
): string {
  if (input.task_status === "success") {
    if (input.actual_end_time) {
      const finished = new Date(input.actual_end_time).toLocaleTimeString("en-US", {
        hour: "numeric",
        minute: "2-digit",
      });
      return `Marked completed · finished ${finished}.`;
    }
    return scheduledEnd
      ? `Marked completed · scheduled end ${scheduledEnd}.`
      : "Marked completed.";
  }
  if (input.outcome_status === "not_started") return "Marked not completed · not started.";
  return input.active_minutes != null
    ? `Marked not completed · ${input.active_minutes} min recorded.`
    : "Marked not completed.";
}

/** Values from the "Edit logged plan" form; times are `datetime-local` strings or "". */
export interface RevisionDraft {
  result: MobileOutcomeStatus;
  actualStart: string;
  actualEnd: string;
  interruptions: string;
  /** Whole percent for a partial result. */
  progress: string;
  minutesSpent: string;
  reason: FailureReasonCode | "";
}

/**
 * Correct a logged outcome without inventing times. A blank time is sent as
 * absent, which keeps the stored value (unknown stays unknown); a stored time
 * can be corrected but not erased. Details the form does not change are kept.
 */
export function buildRevisionInput(
  draft: RevisionDraft,
  existing: Pick<
    Execution,
    "actual_start_time" | "actual_end_time" | "active_minutes" | "outcome_status" | "stopped_early"
  >,
  now = new Date(),
): OutcomeBuild {
  const { result } = draft;
  if (result === "not_started") {
    return {
      ok: true,
      input: {
        task_status: "failed",
        outcome_status: "not_started",
        completion_ratio: 0,
        interruption_count: 0,
        stopped_early: false,
        failure_reason: draft.reason || undefined,
      },
    };
  }

  // Blank interruptions stay unknown (null); a stored count is shown and kept as entered.
  const count = draft.interruptions.trim() === "" ? null : Number(draft.interruptions);
  if (count !== null && (!Number.isInteger(count) || count < 0 || count > 10000)) {
    return { ok: false, error: "Interruptions must be a whole number from 0 to 10000." };
  }
  const percent = Number(draft.progress);
  if (result === "partial" && (draft.progress.trim() === "" || !Number.isInteger(percent) || percent < 1 || percent > 99)) {
    return { ok: false, error: "Enter a completion percentage from 1 to 99." };
  }
  const minutesText = draft.minutesSpent.trim();
  const minutes = minutesText === "" ? null : Number(minutesText);
  if (minutes !== null && (!Number.isInteger(minutes) || minutes < 0 || minutes > MAX_MINUTES_SPENT)) {
    return { ok: false, error: `Minutes spent must be a whole number from 0 to ${MAX_MINUTES_SPENT}.` };
  }

  const times: { actual_start_time?: string; actual_end_time?: string } = {};
  for (const [field, text, stored, label] of [
    ["actual_start_time", draft.actualStart, existing.actual_start_time, "start"],
    ["actual_end_time", draft.actualEnd, existing.actual_end_time, "finish"],
  ] as const) {
    if (!text.trim()) {
      if (stored) return { ok: false, error: `The saved ${label} time can be corrected but not removed.` };
      continue;
    }
    const value = new Date(text);
    if (Number.isNaN(value.getTime())) return { ok: false, error: `Enter a valid ${label} time.` };
    if (value.getTime() > now.getTime() + FUTURE_TOLERANCE_MS) {
      return { ok: false, error: `The ${label} time can’t be in the future.` };
    }
    times[field] = value.toISOString();
  }
  const start = times.actual_start_time ?? existing.actual_start_time;
  const end = times.actual_end_time ?? existing.actual_end_time;
  if (start && end) {
    const elapsed = (new Date(end).getTime() - new Date(start).getTime()) / 60_000;
    if (elapsed < 0) return { ok: false, error: "The finish time must follow the start time." };
    if (minutes !== null && result !== "completed" && minutes > Math.floor(elapsed)) {
      return { ok: false, error: "Minutes spent can’t exceed the time between start and finish." };
    }
  }

  const sameResult = existing.outcome_status === result;
  return {
    ok: true,
    input: {
      task_status: result === "completed" ? "success" : "failed",
      outcome_status: result,
      completion_ratio: result === "completed" ? 1 : result === "partial" ? percent / 100 : 0,
      interruption_count: count,
      stopped_early: sameResult
        ? existing.stopped_early
        : result === "partial" || (result === "abandoned" && minutes !== null && minutes > 0),
      failure_reason: result === "completed" ? undefined : draft.reason || undefined,
      active_minutes: result === "completed" ? existing.active_minutes ?? null : minutes,
      ...times,
    },
  };
}
