"use client";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/app/providers";
import {
  getTasks,
  updateTask,
  reviseAIPlan,
  clearAIPlan,
  ensureAIPlan,
  predictAIPlan,
  createTimeRecommendation,
  selectTimeCandidate,
  type Task,
  type Prediction,
  type TimeCandidate,
  type TimeRecommendation,
} from "@/lib/api";
import {
  localDateString,
  taskTimeInMinutes,
  toStoredTime,
} from "@/lib/mobile-task";
import { readPreferences } from "@/lib/preferences";
import { useDataRefresh } from "@/lib/refresh";
import { useToast } from "@/components/ui/toast";
import { findFreeSlots, overlappingTasks } from "@/lib/scheduling";

export default function SchedulerPage() {
  return (
    <Suspense fallback={<p>Loading schedule…</p>}>
      <Scheduler />
    </Suspense>
  );
}
function Scheduler() {
  const params = useSearchParams();
  const { user } = useAuth();
  const preferences = readPreferences(user?.user_metadata);
  const toast = useToast();
  const [date, setDate] = useState(localDateString);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const [prediction, setPrediction] = useState<Prediction | null>(null);
  const [predicting, setPredicting] = useState(false);
  const [predictionError, setPredictionError] = useState(false);
  const [recommendation, setRecommendation] =
    useState<TimeRecommendation | null>(null);
  const [recommending, setRecommending] = useState(false);
  const [recommendationError, setRecommendationError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const request = useRef(0);
  const load = useCallback(async () => {
    const id = ++request.current;
    setLoading(true);
    setError(false);
    try {
      const data = await getTasks(date);
      if (id === request.current)
        setTasks(
          data.sort(
            (a, b) =>
              taskTimeInMinutes(a.planned_start_time) -
              taskTimeInMinutes(b.planned_start_time),
          ),
        );
    } catch {
      if (id === request.current) {
        setTasks([]);
        setError(true);
      }
    } finally {
      if (id === request.current) setLoading(false);
    }
  }, [date]);
  useEffect(() => {
    void load();
  }, [load]);
  useDataRefresh(load);
  useEffect(() => {
    const day = params.get("date");
    if (
      day &&
      /^\d{4}-\d{2}-\d{2}$/.test(day) &&
      !Number.isNaN(Date.parse(day))
    )
      setDate(day);
    setSelected(params.get("task"));
  }, [params]);
  const task = tasks.find((t) => t.id === selected);
  const successPercent = prediction
    ? Math.round(Math.max(0, Math.min(1, prediction.success_probability)) * 100)
    : null;
  useEffect(() => {
    setRecommendation(null);
    setRecommendationError(null);
  }, [date, task?.id, task?.ai_plan_input_id]);
  useEffect(() => {
    let cancelled = false;
    setPrediction(null);
    setPredictionError(false);
    if (!task) {
      setPredicting(false);
      return;
    }
    setPredicting(true);
    const planIdPromise = task.ai_plan_input_id
      ? Promise.resolve(task.ai_plan_input_id)
      : ensureAIPlan(task);
    planIdPromise
      .then(async (planId) => {
        if (!task.ai_plan_input_id) {
          setTasks((current) =>
            current.map((item) =>
              item.id === task.id ? { ...item, ai_plan_input_id: planId } : item,
            ),
          );
        }
        return predictAIPlan(planId);
      })
      .then((p) => {
        if (!cancelled) setPrediction(p);
      })
      .catch(() => {
        if (!cancelled) setPredictionError(true);
      })
      .finally(() => {
        if (!cancelled) setPredicting(false);
      });
    return () => {
      cancelled = true;
    };
  }, [task?.id, task?.ai_plan_input_id]);
  const conflicts = overlappingTasks(tasks);
  const now = new Date();
  const slots = task
    ? findFreeSlots(
        tasks,
        task,
        preferences.workStart,
        preferences.workEnd,
        date === localDateString() ? now.getHours() * 60 + now.getMinutes() : 0,
      )
    : [];
  async function move(
    minutes: number,
    accepted?: { recommendationId: string; candidateId: string },
  ) {
    if (!task || saving) return;
    setSaving(true);
    const time = toStoredTime(
      `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`,
    );
    try {
      await updateTask(task.id, { planned_start_time: time });
      if (task.ai_plan_input_id) {
        try {
          await reviseAIPlan(task.id, task.ai_plan_input_id, {
            ...task,
            planned_start_time: time,
          });
        } catch {
          clearAIPlan(task.id);
          toast.warn("Time saved", "AI advice could not be refreshed.");
        }
      }
      if (accepted) {
        try {
          await selectTimeCandidate(accepted.recommendationId, accepted.candidateId);
        } catch {
          toast.warn(
            "Time saved",
            "The AI ranking choice could not be recorded, but your plan was moved.",
          );
        }
      }
      toast.success("Plan rescheduled", time);
      setRecommendation(null);
      void load();
    } catch {
      toast.error(
        "Couldn’t change the time",
        "Your original plan is unchanged. Please try again.",
      );
    } finally {
      setSaving(false);
    }
  }
  async function rankTimes() {
    if (!task?.ai_plan_input_id || recommending) return;
    const startMinutes = taskTimeInMinutes(preferences.workStart);
    const endMinutes = taskTimeInMinutes(preferences.workEnd);
    const current = new Date();
    const earliest =
      date === localDateString()
        ? Math.max(startMinutes, Math.ceil((current.getHours() * 60 + current.getMinutes()) / 15) * 15)
        : startMinutes;
    if (earliest + task.planned_duration_min > endMinutes) {
      setRecommendation(null);
      setRecommendationError("No remaining time inside your saved planning hours fits this plan.");
      return;
    }
    const clock = (minutes: number) =>
      `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
    setRecommending(true);
    setRecommendationError(null);
    try {
      const result = await createTimeRecommendation(task.ai_plan_input_id, date, {
        earliestTime: clock(earliest),
        latestTime: clock(endMinutes),
        slotIntervalMinutes: 15,
        minimumBufferMinutes: 15,
      });
      setRecommendation(result);
    } catch {
      setRecommendation(null);
      setRecommendationError(
        "Personalized recommendations are unavailable for this window. The conflict-free times above are still available.",
      );
    } finally {
      setRecommending(false);
    }
  }
  function candidateMinutes(candidate: TimeCandidate) {
    const value = new Date(candidate.candidate_start);
    return value.getHours() * 60 + value.getMinutes();
  }
  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold">Make room in your day</h1>
          <p className="mt-2 text-sm text-slate-500">
            Choose a plan to find a time with a 15-minute buffer.
          </p>
        </div>
        <input
          aria-label="Schedule date"
          className="field !w-auto"
          type="date"
          value={date}
          onChange={(e) => {
            if (e.target.value) setDate(e.target.value);
          }}
        />
      </header>
      {loading ? (
        <p role="status">Loading schedule…</p>
      ) : error ? (
        <div role="alert" className="panel">
          Couldn’t load your schedule.{" "}
          <button className="btn-secondary" onClick={() => void load()}>
            Retry
          </button>
        </div>
      ) : (
        <div className="grid gap-6 xl:grid-cols-2">
          <section className="panel">
            <h2 className="mb-4 text-lg font-semibold">
              {new Date(`${date}T12:00:00`).toLocaleDateString("en-US", {
                month: "long",
                day: "numeric",
                weekday: "long",
              })}
            </h2>
            {!tasks.length ? (
              <p className="text-slate-500">
                No plans for this date.{" "}
                <Link
                  className="underline"
                  href={`/dashboard/habits?date=${date}`}
                >
                  Add a plan
                </Link>
              </p>
            ) : (
              <ul className="space-y-3">
                {tasks.map((t) => (
                  <li key={t.id}>
                    <button
                      onClick={() => setSelected(t.id)}
                      className={`w-full rounded-2xl border p-4 text-left ${t.id === selected ? "border-slate-900 bg-slate-50" : "border-slate-200"}`}
                    >
                      <p className="font-semibold">{t.title}</p>
                      <p className="mt-1 text-sm text-slate-500">
                        {t.planned_start_time} · {t.planned_duration_min} min ·{" "}
                        {t.task_status === "pending"
                          ? "Planned"
                          : t.task_status === "success"
                            ? "Completed"
                            : "Not completed"}
                      </p>
                      {conflicts.has(t.id) && (
                        <p className="mt-2 text-sm text-amber-800">
                          Overlaps another plan
                        </p>
                      )}
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="panel">
            {!task ? (
              <p className="text-slate-500">
                Select a plan to see available times.
              </p>
            ) : (
              <>
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-xl font-semibold">{task.title}</h2>
                  {successPercent !== null && (
                    <span
                      className="rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700"
                      title="Experimental estimate based on the information available when this plan was created"
                    >
                      Estimated success {successPercent}%
                    </span>
                  )}
                </div>
                {prediction?.personalization?.applied && (
                  <div className="mt-3 rounded-xl bg-emerald-50 px-3 py-2 text-xs text-emerald-900">
                    <p className="font-semibold">
                      Personalized using {prediction.personalization.sample_count} previous plans
                    </p>
                    {prediction.personalization.factors[0] && (
                      <p className="mt-1 text-emerald-800">
                        {prediction.personalization.factors[0].message}
                      </p>
                    )}
                  </div>
                )}
                <p className="mt-2 text-sm text-slate-500">
                  {preferences.workStart}–{preferences.workEnd} ·{" "}
                  {task.planned_duration_min} minutes.{" "}
                  <Link className="underline" href="/dashboard/settings">
                    Change planning hours
                  </Link>
                </p>
                {task.task_status !== "pending" ? (
                  <p className="mt-5 text-sm">
                    This plan already has an outcome. Create a new plan to try
                    it again.
                  </p>
                ) : (
                  <>
                    <div className="mt-6 flex items-center justify-between gap-3">
                      <div>
                        <p className="text-xs font-bold uppercase tracking-[0.14em] text-slate-400">
                          Scheduling rules
                        </p>
                        <h3 className="mt-1 font-semibold">Conflict-free times</h3>
                      </div>
                      <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600">
                        15 min buffer
                      </span>
                    </div>
                    {slots.length ? (
                      <div className="mt-3 flex flex-wrap gap-2">
                        {slots.slice(0, 8).map((m) => (
                          <button
                            key={m}
                            className="btn-secondary"
                            disabled={saving}
                            onClick={() => void move(m)}
                          >
                            {toStoredTime(
                              `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}`,
                            )}
                          </button>
                        ))}
                      </div>
                    ) : (
                      <p className="mt-3 text-sm text-amber-800">
                        No buffered slot fits. Try a shorter plan, another date,
                        or wider planning hours.
                      </p>
                    )}
                    <p className="mt-3 text-xs text-slate-500">
                      These options only check planning hours and schedule conflicts.
                      Selecting one saves the change immediately.
                    </p>

                    <div className="mt-6 rounded-2xl border border-violet-200 bg-violet-50 p-4">
                      <div className="flex items-start justify-between gap-4">
                        <div>
                          <p className="text-xs font-bold uppercase tracking-[0.14em] text-violet-700">
                            Personalized recommendation · Experimental
                          </p>
                          <h3 className="mt-1 font-semibold">Which free time fits this plan best?</h3>
                          <p className="mt-2 text-sm leading-relaxed text-slate-600">
                            We compare conflict-free times using plan length, time of day,
                            workload, category, energy, and focus.
                          </p>
                        </div>
                        <button
                          className="shrink-0 rounded-xl bg-violet-700 px-4 py-2.5 text-sm font-bold text-white hover:bg-violet-800 disabled:opacity-50"
                          disabled={recommending || !task.ai_plan_input_id || !slots.length}
                          onClick={() => void rankTimes()}
                        >
                          {recommending ? "Finding times…" : "Get personalized recommendations"}
                        </button>
                      </div>
                      {!task.ai_plan_input_id && (
                        <p className="mt-3 text-xs font-medium text-amber-800">
                          {predictionError
                            ? "We couldn’t prepare recommendations for this plan. Check the backend connection and try again."
                            : "Preparing personalized recommendations for this plan…"}
                        </p>
                      )}
                      {recommendationError && (
                        <p className="mt-3 text-sm text-rose-800" role="alert">
                          {recommendationError}
                        </p>
                      )}
                      {recommendation?.candidates.length ? (
                        <ol className="mt-4 grid gap-2 sm:grid-cols-2">
                          {recommendation.candidates.slice(0, 4).map((candidate) => {
                            const start = new Date(candidate.candidate_start);
                            const end = new Date(candidate.candidate_end);
                            return (
                              <li key={candidate.id}>
                                <button
                                  className="w-full rounded-xl border border-violet-200 bg-white p-3 text-left transition hover:border-violet-500 hover:shadow-sm disabled:opacity-50"
                                  disabled={saving}
                                  onClick={() =>
                                    void move(candidateMinutes(candidate), {
                                      recommendationId: recommendation.id,
                                      candidateId: candidate.id,
                                    })
                                  }
                                >
                                  <span className="flex items-center justify-between gap-2">
                                    <span className="font-bold text-slate-950">
                                      {start.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}
                                      –{end.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}
                                    </span>
                                    <span className="text-right text-xs font-bold text-violet-700">
                                      <span className="block">#{candidate.rank}</span>
                                      <span className="block text-[10px] font-semibold text-violet-600">
                                        Estimated success {Math.round(Math.max(0, Math.min(1, candidate.predicted_success_probability)) * 100)}%
                                      </span>
                                    </span>
                                  </span>
                                  <span className="mt-1 block text-xs text-slate-500">
                                    Conflict-free · personalized fit
                                  </span>
                                  {candidate.reason_snapshot.personalization?.applied && (
                                    <span className="mt-1 block text-[10px] text-violet-700">
                                      Based on {candidate.reason_snapshot.personalization.sample_count} previous plans
                                    </span>
                                  )}
                                </button>
                              </li>
                            );
                          })}
                        </ol>
                      ) : null}
                      <p className="mt-3 text-[11px] leading-relaxed text-violet-800/70">
                        Estimates are guidance and may change as your plan changes.
                      </p>
                    </div>
                  </>
                )}
                <div className="mt-6 border-t border-slate-200 pt-5">
                  <p className="text-xs font-bold uppercase tracking-[0.14em] text-emerald-700">
                    Personalized recommendation
                  </p>
                  <h3 className="mt-1 font-semibold">How to make this plan easier to complete</h3>
                  {predicting ? (
                    <p role="status" className="mt-2 text-sm">
                      Checking guidance…
                    </p>
                  ) : (
                    <>
                      <p className="mt-2 text-sm text-slate-500">
                        {prediction
                          ? "Based on this plan’s estimated success score, the suggestions below highlight practical changes that may make it easier to complete."
                          : "AI guidance is unavailable for this plan. You can still use the schedule checks above."}
                      </p>
                      {prediction?.recommended_actions?.map((a) => (
                        <div
                          key={a.code}
                          className="mt-3 rounded-xl bg-slate-50 p-3"
                        >
                          <p className="text-sm font-semibold">{a.title}</p>
                          <p className="mt-1 text-sm text-slate-600">
                            {a.detail}
                          </p>
                        </div>
                      ))}
                    </>
                  )}
                </div>
              </>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
