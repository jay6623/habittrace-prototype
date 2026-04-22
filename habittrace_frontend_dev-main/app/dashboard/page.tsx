"use client";

import { useEffect, useState } from "react";
import ExecutionTrendChart from "@/components/charts/execution-trend";
import FailurePatternChart from "@/components/charts/failure-pattern";
import CoachChat from "@/components/coach-chat";
import { getAnalyticsSummary, type AnalyticsSummary } from "@/lib/api";

function formatReason(key: string): string {
  const map: Record<string, string> = {
    low_energy:         "Low energy",
    low_focus:          "Low focus",
    start_delay:        "Started late",
    interruptions:      "Interruptions",
    time_underestimate: "Underestimated time",
    schedule_conflict:  "Schedule conflict",
    unexpected_event:   "Unexpected event",
    other:              "Other",
  };
  return map[key] ?? key.replace(/_/g, " ");
}

export default function DashboardPage() {
  const [analytics, setAnalytics] = useState<AnalyticsSummary | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getAnalyticsSummary("week")
      .then(setAnalytics)
      .catch((err) => console.warn("Dashboard data fetch failed:", err))
      .finally(() => setLoading(false));
  }, []);

  const trendLabels   = analytics?.execution_trend.map((p) => p.label)         ?? ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
  const trendPlanned  = analytics?.execution_trend.map((p) => p.planned_mins)   ?? [0,0,0,0,0,0,0];
  const trendCompleted = analytics?.execution_trend.map((p) => p.completed_mins) ?? [0,0,0,0,0,0,0];

  const failureEntries = analytics
    ? Object.entries(analytics.failure_by_reason).sort((a, b) => b[1] - a[1])
    : [];
  const failureLabels = failureEntries.map(([k]) => formatReason(k));
  const failureData   = failureEntries.map(([, v]) => v);

  return (
    <div className="h-[calc(100vh-theme(spacing.28))] flex gap-3">
      {/* Left: AI Coach — full height */}
      <div className="w-[55%] min-h-0">
        <CoachChat />
      </div>

      {/* Right: 3 stacked panels */}
      <div className="flex-1 flex flex-col gap-3 min-h-0">
        {/* Execution Trend */}
        <div className="bg-white rounded-2xl border border-slate-200 p-3 flex-1 min-h-0 flex flex-col">
          <div className="text-sm font-semibold shrink-0">Execution trend</div>
          <div className="text-xs text-slate-500 mb-2 shrink-0">Planned vs completed this week</div>
          <div className="flex-1 min-h-0">
            {loading ? (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">Loading…</div>
            ) : (
              <ExecutionTrendChart labels={trendLabels} planned={trendPlanned} completed={trendCompleted} />
            )}
          </div>
        </div>

        {/* Failure Pattern */}
        <div className="bg-white rounded-2xl border border-slate-200 p-3 flex-1 min-h-0 flex flex-col">
          <div className="text-sm font-semibold shrink-0">Failure pattern mix</div>
          <div className="text-xs text-slate-500 mb-2 shrink-0">Where plans usually break</div>
          <div className="flex-1 min-h-0">
            {loading ? (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">Loading…</div>
            ) : failureLabels.length > 0 ? (
              <FailurePatternChart labels={failureLabels} data={failureData} />
            ) : (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">
                No failure data yet — complete some tasks to see patterns.
              </div>
            )}
          </div>
        </div>

        {/* Weekly Summary */}
        <div className="bg-white rounded-2xl border border-slate-200 p-3 flex-1 min-h-0 flex flex-col">
          <div className="text-sm font-semibold shrink-0">Weekly summary</div>
          <div className="text-xs text-slate-500 mb-2 shrink-0">Your performance this week</div>
          <div className="flex-1 overflow-y-auto min-h-0">
            {analytics ? (
              <div>
                {[
                  { label: "Total tasks",          value: String(analytics.total_tasks) },
                  { label: "Success rate",          value: `${analytics.success_rate}%`,          color: "text-emerald-600" },
                  { label: "Most failed category",  value: analytics.most_failed_category,        color: "text-rose-600" },
                  { label: "Avg interruptions",     value: `${analytics.avg_interruptions} / task` },
                  { label: "Total planned time",    value: `${analytics.total_planned_minutes} min` },
                ].map(({ label, value, color }) => (
                  <div key={label} className="flex items-center justify-between py-2 border-b border-slate-100 last:border-0">
                    <span className="text-xs text-slate-600">{label}</span>
                    <span className={`text-xs font-semibold ${color ?? ""}`}>{value}</span>
                  </div>
                ))}
              </div>
            ) : (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">
                {loading ? "Loading…" : "No data yet. Start tracking tasks!"}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
