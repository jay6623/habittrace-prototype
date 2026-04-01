"use client";

import { useState, useEffect } from "react";
import { getTasks, predict, type Task, type Prediction } from "@/lib/api";

// ── Types ─────────────────────────────────────────────────────────────────
interface TaskWithPred extends Task {
  prediction?: Prediction;
  predLoading?: boolean;
}

// ── Helpers ───────────────────────────────────────────────────────────────
const HOURS = Array.from({ length: 17 }, (_, i) => i + 6); // 6 AM – 10 PM

function parseHour(timeStr: string): number {
  if (!timeStr) return -1;
  const s = timeStr.trim().toLowerCase();
  const match = s.match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/);
  if (!match) return -1;
  let h = parseInt(match[1]);
  const meridiem = match[3];
  if (meridiem === "pm" && h !== 12) h += 12;
  if (meridiem === "am" && h === 12) h = 0;
  return h;
}

function formatHour(h: number) {
  if (h === 0) return "12 AM";
  if (h < 12) return `${h} AM`;
  if (h === 12) return "12 PM";
  return `${h - 12} PM`;
}

function pctColor(pct: number) {
  if (pct >= 70) return "text-emerald-600";
  if (pct >= 50) return "text-amber-500";
  return "text-rose-500";
}

function pctBg(pct: number) {
  if (pct >= 70) return "bg-emerald-100 border-emerald-200";
  if (pct >= 50) return "bg-amber-50 border-amber-200";
  return "bg-rose-50 border-rose-200";
}

const categoryColors: Record<string, string> = {
  Study:             "bg-sky-500",
  Work:              "bg-violet-500",
  Chores:            "bg-amber-500",
  "Fitness/Health":  "bg-emerald-500",
  "Errands/Admin":   "bg-slate-500",
  "Hobbies/Leisure": "bg-rose-500",
  Social:            "bg-indigo-500",
  Other:             "bg-gray-400",
};

// ── Component ─────────────────────────────────────────────────────────────
export default function SchedulerPage() {
  const [tasks, setTasks] = useState<TaskWithPred[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedTask, setSelectedTask] = useState<TaskWithPred | null>(null);
  const [energyLevel, setEnergyLevel] = useState(3);
  const [focusLevel, setFocusLevel] = useState(3);

  const today = new Date();
  const currentHour = today.getHours();

  // ── Load today's tasks + fire predictions ─────────────────────────────
  useEffect(() => {
    const dateStr = today.toISOString().split("T")[0];
    setLoading(true);
    getTasks(dateStr)
      .then((serverTasks) => {
        const withPred = serverTasks.map((t) => ({ ...t, predLoading: true }));
        setTasks(withPred);

        // Fire prediction for each pending task
        withPred.forEach((t) => {
          if (t.task_status !== "pending") {
            setTasks((prev) =>
              prev.map((x) => x.id === t.id ? { ...x, predLoading: false } : x)
            );
            return;
          }
          predict({
            task_category: t.task_category,
            planned_start_time: t.planned_start_time,
            planned_date: t.planned_date,
            planned_duration_min: t.planned_duration_min,
            importance: t.importance,
            energy_level: energyLevel,
            focus_level: focusLevel,
            total_tasks_today: serverTasks.length,
          })
            .then((pred) => {
              setTasks((prev) =>
                prev.map((x) =>
                  x.id === t.id ? { ...x, prediction: pred, predLoading: false } : x
                )
              );
            })
            .catch(() => {
              setTasks((prev) =>
                prev.map((x) => x.id === t.id ? { ...x, predLoading: false } : x)
              );
            });
        });
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Re-run predictions when energy/focus changes
  function repredict() {
    tasks.forEach((t) => {
      if (t.task_status !== "pending") return;
      setTasks((prev) =>
        prev.map((x) => x.id === t.id ? { ...x, predLoading: true } : x)
      );
      predict({
        task_category: t.task_category,
        planned_start_time: t.planned_start_time,
        planned_date: t.planned_date,
        planned_duration_min: t.planned_duration_min,
        importance: t.importance,
        energy_level: energyLevel,
        focus_level: focusLevel,
        total_tasks_today: tasks.length,
      })
        .then((pred) => {
          setTasks((prev) =>
            prev.map((x) =>
              x.id === t.id ? { ...x, prediction: pred, predLoading: false } : x
            )
          );
        })
        .catch(() => {
          setTasks((prev) =>
            prev.map((x) => x.id === t.id ? { ...x, predLoading: false } : x)
          );
        });
    });
  }

  // Sort tasks by planned hour
  const sortedTasks = [...tasks].sort((a, b) => {
    return parseHour(a.planned_start_time) - parseHour(b.planned_start_time);
  });

  const pendingTasks = sortedTasks.filter((t) => t.task_status === "pending");
  const doneTasks = sortedTasks.filter((t) => t.task_status !== "pending");

  const avgSuccess =
    pendingTasks.length > 0
      ? Math.round(
          pendingTasks.reduce(
            (s, t) => s + (t.prediction ? t.prediction.success_probability * 100 : 0),
            0
          ) / pendingTasks.length
        )
      : null;

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="text-sm text-slate-500">Scheduler</div>
          <h1 className="text-2xl font-bold">Today&apos;s Schedule</h1>
        </div>
        <div className="text-sm text-slate-500">
          {today.toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric" })}
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-5">
        {/* ── Timeline ─────────────────────────────────────────────────── */}
        <div className="xl:col-span-2 space-y-4">
          {/* Current energy/focus override */}
          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-3">Current state</div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="text-xs text-slate-500 mb-2">Energy level</div>
                <div className="flex gap-1.5">
                  {[1,2,3,4,5].map((n) => (
                    <button
                      key={n}
                      onClick={() => setEnergyLevel(n)}
                      className={`h-8 w-8 rounded-lg text-xs font-semibold transition-colors ${
                        n <= energyLevel
                          ? "bg-amber-400 text-white"
                          : "bg-slate-100 text-slate-400 hover:bg-slate-200"
                      }`}
                    >{n}</button>
                  ))}
                </div>
              </div>
              <div>
                <div className="text-xs text-slate-500 mb-2">Focus level</div>
                <div className="flex gap-1.5">
                  {[1,2,3,4,5].map((n) => (
                    <button
                      key={n}
                      onClick={() => setFocusLevel(n)}
                      className={`h-8 w-8 rounded-lg text-xs font-semibold transition-colors ${
                        n <= focusLevel
                          ? "bg-sky-400 text-white"
                          : "bg-slate-100 text-slate-400 hover:bg-slate-200"
                      }`}
                    >{n}</button>
                  ))}
                </div>
              </div>
            </div>
            <button
              onClick={repredict}
              className="mt-3 px-4 py-2 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors"
            >
              Re-calculate predictions
            </button>
          </div>

          {/* Timeline */}
          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-4">Day timeline</div>

            {loading ? (
              <div className="py-12 text-center text-sm text-slate-400 animate-pulse">
                Loading schedule…
              </div>
            ) : (
              <div className="relative">
                {HOURS.map((hour) => {
                  const tasksThisHour = sortedTasks.filter(
                    (t) => parseHour(t.planned_start_time) === hour
                  );
                  const isCurrentHour = hour === currentHour;

                  return (
                    <div key={hour} className="flex gap-3 min-h-[52px]">
                      {/* Hour label */}
                      <div className="w-14 shrink-0 pt-1 text-xs text-slate-400 text-right">
                        {formatHour(hour)}
                      </div>

                      {/* Line + tasks */}
                      <div className="flex-1 border-t border-slate-100 pt-1 pb-2 relative">
                        {isCurrentHour && (
                          <div className="absolute -top-px left-0 right-0 h-0.5 bg-rose-400 z-10" />
                        )}
                        {tasksThisHour.map((task) => {
                          const pct = task.prediction
                            ? Math.round(task.prediction.success_probability * 100)
                            : null;
                          return (
                            <button
                              key={task.id}
                              onClick={() => setSelectedTask(task)}
                              className={`mb-1.5 w-full text-left rounded-xl border px-3 py-2 transition-all hover:shadow-sm ${
                                selectedTask?.id === task.id
                                  ? "ring-2 ring-slate-900"
                                  : ""
                              } ${
                                task.task_status === "success"
                                  ? "bg-emerald-50 border-emerald-200"
                                  : task.task_status === "failed"
                                  ? "bg-rose-50 border-rose-200"
                                  : pct !== null
                                  ? pctBg(pct)
                                  : "bg-white border-slate-200"
                              }`}
                            >
                              <div className="flex items-center gap-2">
                                <div
                                  className={`h-2 w-2 rounded-full shrink-0 ${
                                    categoryColors[task.task_category] ?? "bg-slate-400"
                                  }`}
                                />
                                <span className="text-sm font-medium truncate flex-1">
                                  {task.title}
                                </span>
                                <span className="text-xs text-slate-500 shrink-0">
                                  {task.planned_duration_min}m
                                </span>
                                {task.task_status === "success" && (
                                  <span className="text-xs text-emerald-600 font-medium shrink-0">Done</span>
                                )}
                                {task.task_status === "failed" && (
                                  <span className="text-xs text-rose-600 font-medium shrink-0">Failed</span>
                                )}
                                {task.task_status === "pending" && (
                                  task.predLoading ? (
                                    <span className="text-xs text-slate-300 shrink-0">…</span>
                                  ) : pct !== null ? (
                                    <span className={`text-xs font-semibold shrink-0 ${pctColor(pct)}`}>
                                      {pct}%
                                    </span>
                                  ) : null
                                )}
                              </div>
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  );
                })}

                {sortedTasks.length === 0 && (
                  <div className="py-8 text-center text-sm text-slate-400">
                    No tasks scheduled today. Add tasks in the Habits tab.
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* ── Right panel ──────────────────────────────────────────────── */}
        <div className="space-y-4">
          {/* Summary card */}
          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-3">Today&apos;s overview</div>
            <div className="space-y-2.5">
              <div className="flex justify-between text-sm">
                <span className="text-slate-500">Total tasks</span>
                <span className="font-semibold">{tasks.length}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-slate-500">Completed</span>
                <span className="font-semibold text-emerald-600">{doneTasks.filter(t => t.task_status === "success").length}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-slate-500">Remaining</span>
                <span className="font-semibold">{pendingTasks.length}</span>
              </div>
              {avgSuccess !== null && (
                <div className="flex justify-between text-sm">
                  <span className="text-slate-500">Avg predicted success</span>
                  <span className={`font-semibold ${pctColor(avgSuccess)}`}>{avgSuccess}%</span>
                </div>
              )}
              <div className="flex justify-between text-sm">
                <span className="text-slate-500">Planned time</span>
                <span className="font-semibold">
                  {tasks.reduce((s, t) => s + t.planned_duration_min, 0)} min
                </span>
              </div>
            </div>
          </div>

          {/* Selected task detail */}
          {selectedTask ? (
            <div className="bg-white rounded-2xl border border-slate-200 p-5">
              <div className="flex items-center justify-between mb-3">
                <div className="font-semibold">Task detail</div>
                <button
                  onClick={() => setSelectedTask(null)}
                  className="text-slate-400 hover:text-slate-600"
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                    <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
                  </svg>
                </button>
              </div>

              <div className="space-y-2">
                <div className="font-medium">{selectedTask.title}</div>
                <div className="flex flex-wrap gap-1.5">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                    {selectedTask.task_category}
                  </span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                    {selectedTask.planned_start_time}
                  </span>
                  <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                    {selectedTask.planned_duration_min} min
                  </span>
                </div>

                <div className="grid grid-cols-3 gap-2 mt-2">
                  {[
                    { label: "Importance", value: selectedTask.importance },
                    { label: "Energy", value: selectedTask.energy_level },
                    { label: "Focus", value: selectedTask.focus_level },
                  ].map(({ label, value }) => (
                    <div key={label} className="bg-slate-50 rounded-xl p-2 text-center">
                      <div className="text-xs text-slate-500">{label}</div>
                      <div className="text-sm font-semibold mt-0.5">{value}/5</div>
                    </div>
                  ))}
                </div>

                {selectedTask.prediction && (
                  <div className="mt-3 space-y-2">
                    <div className={`rounded-xl p-3 border ${pctBg(Math.round(selectedTask.prediction.success_probability * 100))}`}>
                      <div className="text-xs text-slate-500">Success probability</div>
                      <div className={`text-2xl font-bold mt-0.5 ${pctColor(Math.round(selectedTask.prediction.success_probability * 100))}`}>
                        {Math.round(selectedTask.prediction.success_probability * 100)}%
                      </div>
                    </div>

                    {selectedTask.prediction.predicted_failure_reason && (
                      <div className="rounded-xl bg-amber-50 border border-amber-100 p-3">
                        <div className="text-xs text-amber-700 font-medium">Watch out for</div>
                        <div className="text-sm font-semibold text-amber-900 mt-0.5">
                          {selectedTask.prediction.predicted_failure_reason.replace(/_/g, " ")}
                        </div>
                      </div>
                    )}

                    {selectedTask.prediction.top_negative_factors.length > 0 && (
                      <div>
                        <div className="text-xs text-slate-500 mb-1.5">Risk factors</div>
                        {selectedTask.prediction.top_negative_factors.slice(0, 3).map((f, i) => (
                          <div key={i} className="flex justify-between text-xs py-1 border-b border-slate-50 last:border-0">
                            <span className="text-slate-600">{f.feature.replace(/_/g, " ")}</span>
                            <span className="text-rose-500 font-medium">{f.contribution.toFixed(2)}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          ) : (
            <div className="bg-white rounded-2xl border border-slate-200 p-5">
              <div className="font-semibold mb-2">Task detail</div>
              <div className="text-sm text-slate-400">
                Click a task in the timeline to see AI predictions and risk factors.
              </div>
            </div>
          )}

          {/* AI Tip */}
          {pendingTasks.length > 0 && (
            <div className="bg-slate-900 text-white rounded-2xl p-5">
              <div className="text-sm font-semibold mb-1">AI tip</div>
              <div className="text-xs text-slate-300">
                {(() => {
                  const lowest = pendingTasks.reduce((min, t) =>
                    (t.prediction?.success_probability ?? 1) <
                    (min.prediction?.success_probability ?? 1)
                      ? t
                      : min,
                    pendingTasks[0]
                  );
                  const pct = lowest.prediction
                    ? Math.round(lowest.prediction.success_probability * 100)
                    : null;
                  if (!pct) return "Add tasks and log results to get personalized AI suggestions.";
                  if (pct < 50)
                    return `"${lowest.title}" has only ${pct}% predicted success. Consider rescheduling or breaking it into smaller steps.`;
                  return `Your schedule looks manageable. Stay focused during high-importance tasks.`;
                })()}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
