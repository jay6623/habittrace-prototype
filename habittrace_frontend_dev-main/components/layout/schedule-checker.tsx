"use client";

import { useEffect, useState, useCallback } from "react";
import { getPlanHealth, type PlanHealth, type TaskSummary } from "@/lib/api";

// ── Helpers ───────────────────────────────────────────────────────────────
const LEVEL_DOT: Record<string, string> = {
  high:   "bg-rose-400",
  medium: "bg-amber-400",
  low:    "bg-sky-400",
};

const LEVEL_TEXT: Record<string, string> = {
  high:   "text-rose-600",
  medium: "text-amber-600",
  low:    "text-sky-600",
};

function successBarColor(pct: number) {
  if (pct >= 70) return "bg-emerald-400";
  if (pct >= 50) return "bg-amber-400";
  return "bg-rose-400";
}

function predBadge(p: number | null) {
  if (p === null) return null;
  const pct = Math.round(p * 100);
  if (pct >= 70) return { text: `${pct}%`, cls: "text-emerald-600" };
  if (pct >= 50) return { text: `${pct}%`, cls: "text-amber-500" };
  return { text: `${pct}%`, cls: "text-rose-500" };
}

const statusDot: Record<TaskSummary["task_status"], string> = {
  success: "bg-emerald-400",
  failed:  "bg-rose-400",
  pending: "bg-slate-300",
};

const categoryDot: Record<string, string> = {
  Study:             "bg-sky-400",
  Work:              "bg-violet-400",
  Chores:            "bg-amber-400",
  "Fitness/Health":  "bg-emerald-400",
  "Errands/Admin":   "bg-slate-400",
  "Hobbies/Leisure": "bg-rose-400",
  Social:            "bg-indigo-400",
  Other:             "bg-gray-400",
};

// ── Component ─────────────────────────────────────────────────────────────
export default function ScheduleChecker() {
  const [health, setHealth] = useState<PlanHealth | null>(null);
  const [loading, setLoading] = useState(true);
  const [apiError, setApiError] = useState(false);

  const fetchHealth = useCallback(() => {
    setLoading(true);
    setApiError(false);
    getPlanHealth()
      .then((data) => {
        setHealth(data);
        setApiError(false);
      })
      .catch(() => {
        setApiError(true);
        setHealth(null);
      })
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  const successPct = health
    ? Math.round(health.overall_success_probability * 100)
    : 0;

  const pendingTasks = health?.tasks.filter((t) => t.task_status === "pending") ?? [];
  const doneTasks    = health?.tasks.filter((t) => t.task_status !== "pending") ?? [];

  return (
    <aside className="w-[300px] min-h-screen bg-white border-l border-slate-200 flex flex-col">
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <div className="p-5 border-b border-slate-200">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs text-slate-500">Schedule checker</div>
            <div className="font-semibold text-sm">Today&apos;s plan health</div>
          </div>
          <button
            onClick={fetchHealth}
            disabled={loading}
            title="Refresh"
            className="h-8 w-8 rounded-xl bg-slate-100 hover:bg-slate-200 grid place-items-center transition-colors disabled:opacity-40"
          >
            <svg
              width="14" height="14" viewBox="0 0 24 24" fill="none"
              className={loading ? "animate-spin" : ""}
            >
              <path
                d="M4 4v5h5M20 20v-5h-5M4 9a9 9 0 0114.93-4.93M20 15a9 9 0 01-14.93 4.93"
                stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
              />
            </svg>
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-3">

        {/* ── Error state ──────────────────────────────────────────────── */}
        {apiError && (
          <div className="rounded-2xl bg-amber-50 border border-amber-100 p-4">
            <div className="text-sm font-medium text-amber-800">Backend not reachable</div>
            <div className="text-xs text-amber-600 mt-1">
              Start the backend server to see real plan health data.
            </div>
            <button
              onClick={fetchHealth}
              className="mt-2 text-xs px-3 py-1.5 rounded-lg bg-amber-100 hover:bg-amber-200 text-amber-800 transition-colors"
            >
              Retry
            </button>
          </div>
        )}

        {/* ── Loading skeleton ─────────────────────────────────────────── */}
        {loading && (
          <div className="space-y-3 animate-pulse">
            <div className="h-20 rounded-2xl bg-slate-100" />
            <div className="h-28 rounded-2xl bg-slate-100" />
            <div className="h-32 rounded-2xl bg-slate-100" />
          </div>
        )}

        {/* ── No tasks state ───────────────────────────────────────────── */}
        {!loading && !apiError && health && health.task_count === 0 && (
          <div className="rounded-2xl bg-slate-50 border border-slate-200 p-4">
            <div className="text-sm font-medium text-slate-700">No tasks today</div>
            <div className="text-xs text-slate-500 mt-1">
              Add tasks in the Habits tab to see plan health analysis.
            </div>
          </div>
        )}

        {/* ── Success probability bar ──────────────────────────────────── */}
        {!loading && !apiError && health && health.task_count > 0 && (
          <>
            <div className="bg-white rounded-2xl border border-slate-200 p-4">
              <div className="flex items-center justify-between mb-2">
                <div className="text-xs font-medium text-slate-600">Overall success</div>
                <div className={`text-sm font-bold ${
                  successPct >= 70 ? "text-emerald-600" :
                  successPct >= 50 ? "text-amber-500" : "text-rose-500"
                }`}>
                  {successPct}%
                </div>
              </div>
              <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-700 ${successBarColor(successPct)}`}
                  style={{ width: `${successPct}%` }}
                />
              </div>
              <div className="mt-2 text-xs text-slate-500">
                {health.task_count} task{health.task_count !== 1 ? "s" : ""} planned ·{" "}
                {doneTasks.filter(t => t.task_status === "success").length} done ·{" "}
                {pendingTasks.length} remaining
              </div>
            </div>

            {/* ── Today's tasks ──────────────────────────────────────── */}
            <div className="bg-white rounded-2xl border border-slate-200 p-4">
              <div className="text-xs font-medium text-slate-600 mb-3">Today&apos;s tasks</div>
              <div className="space-y-2.5">
                {health.tasks
                  .slice()
                  .sort((a, b) => {
                    // pending first, then sort by start time
                    if (a.task_status === "pending" && b.task_status !== "pending") return -1;
                    if (a.task_status !== "pending" && b.task_status === "pending") return 1;
                    return a.planned_start_time.localeCompare(b.planned_start_time);
                  })
                  .map((task) => {
                    const badge = predBadge(task.predicted_success);
                    return (
                      <div key={task.id} className="flex items-start gap-2.5">
                        {/* Status dot */}
                        <div className={`mt-1 h-2 w-2 rounded-full shrink-0 ${
                          task.task_status !== "pending"
                            ? statusDot[task.task_status]
                            : categoryDot[task.task_category] ?? "bg-slate-300"
                        }`} />
                        <div className="flex-1 min-w-0">
                          <div className={`text-xs font-medium truncate ${
                            task.task_status === "success" ? "text-slate-400 line-through" :
                            task.task_status === "failed"  ? "text-slate-400 line-through" :
                            "text-slate-700"
                          }`}>
                            {task.title}
                          </div>
                          <div className="text-xs text-slate-400 mt-0.5">
                            {task.planned_start_time} · {task.planned_duration_min}m
                          </div>
                        </div>
                        {/* ML prediction badge (only for pending) */}
                        {task.task_status === "pending" && badge && (
                          <span className={`text-xs font-semibold shrink-0 ${badge.cls}`}>
                            {badge.text}
                          </span>
                        )}
                        {task.task_status === "success" && (
                          <span className="text-xs text-emerald-500 shrink-0">✓</span>
                        )}
                        {task.task_status === "failed" && (
                          <span className="text-xs text-rose-400 shrink-0">✗</span>
                        )}
                      </div>
                    );
                  })}
              </div>
            </div>

            {/* ── Detected risks ─────────────────────────────────────── */}
            {health.risks.length > 0 ? (
              <div className="bg-white rounded-2xl border border-slate-200 p-4">
                <div className="text-xs font-medium text-slate-600 mb-3">Detected risks</div>
                <div className="space-y-3">
                  {health.risks.map((risk, i) => (
                    <div key={i} className="flex items-start gap-2.5">
                      <div className={`mt-1.5 h-2 w-2 rounded-full shrink-0 ${LEVEL_DOT[risk.level] ?? "bg-slate-300"}`} />
                      <div>
                        <div className={`text-xs font-semibold ${LEVEL_TEXT[risk.level] ?? "text-slate-700"}`}>
                          {risk.title}
                        </div>
                        <div className="text-xs text-slate-500 mt-0.5">{risk.detail}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="rounded-2xl bg-emerald-50 border border-emerald-100 p-4">
                <div className="text-xs font-medium text-emerald-800">Plan looks healthy</div>
                <div className="text-xs text-emerald-600 mt-1">
                  No significant risk patterns detected for today.
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Footer note ──────────────────────────────────────────────────── */}
      {!loading && !apiError && health && health.task_count > 0 && (
        <div className="p-4 border-t border-slate-100">
          <div className="text-xs text-slate-400 text-center">
            Predictions powered by your ML model
          </div>
        </div>
      )}
    </aside>
  );
}
