"use client";
import { useRef, useState } from "react";
import {
  applyPlanChoice,
  comparePlanChoices,
  recordComparisonViewed,
  type PlanComparison,
  type Task,
} from "@/lib/api";
import { describeApiError } from "@/lib/group";
import Dialog from "@/components/ui/dialog";

export default function PlanDecisions({
  task,
  onClose,
  onApplied,
}: {
  task: Task;
  onClose: () => void;
  onApplied: () => void;
}) {
  const [comparison, setComparison] = useState<PlanComparison | null>(null);
  const [choice, setChoice] = useState("");
  const [remaining, setRemaining] = useState("");
  const [energy, setEnergy] = useState(3);
  const [focus, setFocus] = useState(3);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [auditWarning, setAuditWarning] = useState(false);
  const lock = useRef(false);
  async function compare() {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError(null);
    try {
      const result = await comparePlanChoices(
        task.id,
        remaining ? Number(remaining) : undefined,
        energy,
        focus,
      );
      setComparison(result);
      setChoice(result.options.find((o) => o.available)?.id || "");
      // Record exposure after the cards have had a chance to render, separate from generation.
      requestAnimationFrame(() =>
        requestAnimationFrame(
          () =>
            void recordComparisonViewed(result.id).catch(() =>
              setAuditWarning(true),
            ),
        ),
      );
    } catch (caught) {
      setError(
        describeApiError(
          caught,
          "We couldn't compare this plan. Your plan has not changed.",
        ),
      );
    } finally {
      setBusy(false);
      lock.current = false;
    }
  }
  async function apply() {
    if (!comparison || !choice || lock.current) return;
    lock.current = true;
    setBusy(true);
    setError(null);
    try {
      await applyPlanChoice(comparison.id, choice);
      setSaved(true);
      onApplied();
    } catch (caught) {
      setError(
        describeApiError(
          caught,
          "We couldn't apply this choice. Retry the same choice safely, or compare again.",
        ),
      );
    } finally {
      setBusy(false);
      lock.current = false;
    }
  }
  const chosen = comparison?.options.find((o) => o.id === choice);
  return (
    <Dialog title="Find a plan that fits" onClose={onClose} busy={busy}>
      <p className="font-semibold text-slate-900">{task.title}</p>
      <p className="mt-1 text-xs text-slate-500">
        {task.task_status === "pending"
          ? "Current schedule"
          : "Previous attempt"}
        : {task.planned_date} · {task.planned_start_time} ·{" "}
        {task.planned_duration_min} min ({task.timezone_name || "UTC"})
      </p>
      <p className="mt-1 text-sm text-slate-500">
        Compare complete alternatives. Nothing in your schedule changes until
        you confirm. Comparisons are saved privately for estimate review.
      </p>
      {saved ? (
        <div className="mt-5 rounded-2xl bg-emerald-50 p-5">
          <p role="status" className="font-semibold text-emerald-900">
            Your new plan is ready
          </p>
          <p className="mt-1 text-sm">
            Previous results are preserved. Each new block can be recorded
            separately in Plans.
          </p>
          <button className="btn-primary mt-4" onClick={onClose}>
            Back to my plans
          </button>
        </div>
      ) : (
        <>
          <form
            className="my-5 space-y-3"
            onSubmit={(e) => {
              e.preventDefault();
              void compare();
            }}
          >
            <details className="rounded-xl border border-slate-200 p-3">
              <summary className="cursor-pointer text-sm font-medium">
                Adjust my estimate & expected energy
              </summary>
              <p className="my-2 text-xs text-slate-500">
                Energy and focus stay the same across alternatives. They are
                private.
              </p>
              <label className="block text-sm">
                My remaining work estimate (optional, minutes)
                <input
                  className="field mt-1"
                  type="number"
                  min="1"
                  max="720"
                  value={remaining}
                  disabled={busy}
                  onChange={(e) => {
                    setRemaining(e.target.value);
                    setComparison(null);
                  }}
                  placeholder="Use my history and recorded progress"
                />
              </label>
              <div className="mt-3 grid grid-cols-2 gap-3">
                {[
                  { label: "Expected energy", value: energy, set: setEnergy },
                  { label: "Expected focus", value: focus, set: setFocus },
                ].map((x) => (
                  <label key={x.label} className="text-sm">
                    {x.label}
                    <select
                      className="field mt-1"
                      value={x.value}
                      disabled={busy}
                      onChange={(e) => {
                        x.set(Number(e.target.value));
                        setComparison(null);
                      }}
                    >
                      {[1, 2, 3, 4, 5].map((n) => (
                        <option key={n} value={n}>
                          {n} / 5{" "}
                          {n === 1
                            ? "Low"
                            : n === 3
                              ? "Moderate"
                              : n === 5
                                ? "High"
                                : ""}
                        </option>
                      ))}
                    </select>
                  </label>
                ))}
              </div>
            </details>
            <button className="btn-secondary w-full" disabled={busy}>
              {busy
                ? "Checking your options…"
                : comparison
                  ? "Refresh comparison"
                  : "Compare my options"}
            </button>
          </form>
          {comparison && (
            <div className="space-y-4">
              <section
                className="rounded-2xl bg-slate-50 p-4 text-sm"
                aria-label="What this is based on"
              >
                <p className="font-semibold">What this is based on</p>
                <p className="mt-1">
                  {comparison.evidence.history_samples} past outcome records ·{" "}
                  {comparison.evidence.history_samples < 5
                    ? "Early guidance — little history yet"
                    : "History available — review the evidence"}
                </p>
                {comparison.evidence.duration.available ? (
                  <p className="mt-2">
                    Comparable recorded durations:{" "}
                    <strong>
                      {comparison.evidence.duration.observed_lower_minutes}–
                      {comparison.evidence.duration.observed_upper_minutes} min
                    </strong>{" "}
                    ({comparison.evidence.duration.sample_count} records). This
                    is an observed range, not a guarantee.
                  </p>
                ) : (
                  <p className="mt-2 text-slate-500">
                    Not enough comparable duration records yet. Your planned
                    duration is the starting estimate.
                  </p>
                )}
                {comparison.evidence.continuation && (
                  <p className="mt-2">
                    Recorded progress:{" "}
                    {comparison.evidence.progress_ratio === null
                      ? "not reported"
                      : `${Math.round(comparison.evidence.progress_ratio * 100)}%`}
                    . Next estimate:{" "}
                    <strong>{comparison.evidence.remaining_minutes} min</strong>
                    . You can override it above. This creates a next attempt and
                    preserves the earlier result.
                  </p>
                )}
                {comparison.evidence.history_factors.map((factor, i) => (
                  <p className="mt-2" key={i}>
                    {factor.message} ({factor.sample_count} records)
                  </p>
                ))}
              </section>
              <fieldset disabled={busy} className="space-y-3">
                <legend className="mb-2 font-semibold">
                  Choose an approach
                </legend>
                {comparison.options.map((option) => (
                  <label
                    key={option.id}
                    className={`block rounded-2xl border-2 p-4 ${!option.available ? "border-slate-100 bg-slate-50 text-slate-400" : choice === option.id ? "border-violet-600 bg-violet-50" : "border-slate-200 bg-white"}`}
                  >
                    <span className="flex items-center gap-2">
                      <input
                        type="radio"
                        name="plan-choice"
                        checked={choice === option.id}
                        disabled={!option.available}
                        onChange={() => setChoice(option.id)}
                      />
                      <span className="font-semibold">{option.title}</span>
                      <span className="ml-auto text-sm">
                        {option.total_minutes} min
                      </span>
                    </span>
                    <span className="mt-1 block text-sm">
                      {option.description}
                    </span>
                    {option.blocks.map((block, i) => (
                      <span
                        key={i}
                        className="mt-3 block rounded-xl bg-white/70 p-3 text-sm"
                      >
                        <span className="block font-medium">
                          {option.blocks.length > 1 ? `Block ${i + 1} · ` : ""}
                          {new Date(block.planned_start).toLocaleString([], {
                            timeZone: comparison.timezone_name,
                            weekday: "short",
                            month: "short",
                            day: "numeric",
                            hour: "numeric",
                            minute: "2-digit",
                          })}{" "}
                          · {block.duration_minutes} min
                        </span>
                        <span className="mt-1 block text-xs text-slate-600">
                          {block.daily_minutes} min scheduled that day
                          {block.deadline_slack_minutes !== null
                            ? ` · ${Math.round(block.deadline_slack_minutes / 60)}h left before deadline`
                            : ""}
                        </span>
                        <span className="mt-1 block text-xs text-violet-800">
                          {block.success_probability === null
                            ? "Model estimate unavailable"
                            : `${Math.round(block.success_probability * 100)}% experimental estimate for this block`}
                        </span>
                      </span>
                    ))}
                    {option.unavailable_reasons.map((reason) => (
                      <span
                        className="mt-2 block text-sm text-rose-700"
                        key={reason}
                      >
                        {reason}
                      </span>
                    ))}
                  </label>
                ))}
              </fieldset>
              <p className="text-xs leading-relaxed text-slate-500">
                Scores refer to individual blocks, not completing the whole
                task. Comparing estimates does not prove that a change will
                improve your outcome. History count describes evidence, not
                prediction accuracy.
              </p>
              <details className="text-xs text-slate-500">
                <summary className="cursor-pointer">
                  How these estimates are used
                </summary>
                <p className="mt-2">
                  {comparison.evidence.note} Your displayed options, choice,
                  model version and later linked results are recorded privately
                  to evaluate estimates. Unrecorded outcomes are not treated as
                  failures.
                </p>
              </details>
              {comparison.warnings.map((w) => (
                <p key={w} className="text-sm text-amber-800">
                  {w}
                </p>
              ))}
              {auditWarning && (
                <p className="text-xs text-amber-800">
                  We couldn’t record that this comparison was displayed.
                  Planning still works.
                </p>
              )}
              {chosen && (
                <div className="sticky bottom-0 rounded-2xl border border-violet-200 bg-white p-4 shadow-sm">
                  <p className="text-sm">
                    Ready to apply: <strong>{chosen.title}</strong> ·{" "}
                    {chosen.blocks.length} block
                    {chosen.blocks.length > 1 ? "s" : ""}
                  </p>
                  <button
                    className="btn-primary mt-3 w-full"
                    disabled={busy}
                    onClick={() => void apply()}
                  >
                    {busy ? "Saving…" : "Confirm this plan"}
                  </button>
                </div>
              )}
            </div>
          )}
        </>
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
