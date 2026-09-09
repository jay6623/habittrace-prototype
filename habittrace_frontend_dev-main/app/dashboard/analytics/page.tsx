"use client";

import { useState, useEffect, useCallback } from "react";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from "chart.js";
import Link from "next/link";
import { useDataRefresh } from "@/lib/refresh";
import { Line, Bar, Doughnut } from "react-chartjs-2";
import { getAnalyticsSummary, type AnalyticsSummary } from "@/lib/api";

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  ArcElement,
  Title,
  Tooltip,
  Legend,
  Filler,
);

// ── Shared chart styling ────────────────────────────────────────────────────
const tooltipStyle = {
  backgroundColor: "#0f172a",
  titleFont: { size: 13 },
  bodyFont: { size: 12 },
  padding: 12,
  cornerRadius: 12,
  displayColors: false,
};

// ── Fallback / placeholder data (shown while loading or on error) ───────────
const FALLBACK: AnalyticsSummary = {
  period: "week",
  total_tasks: 0,
  success_rate: 0,
  total_planned_minutes: 0,
  avg_importance: 0,
  avg_interruptions: 0,
  most_failed_category: "—",
  best_time_of_day: "—",
  failure_by_category: {},
  failure_by_reason: {},
  execution_trend: [
    { label: "Mon", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Tue", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Wed", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Thu", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Fri", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Sat", planned_mins: 0, completed_mins: 0, success_rate: 0 },
    { label: "Sun", planned_mins: 0, completed_mins: 0, success_rate: 0 },
  ],
  success_by_hour: {
    "6-9 AM": 0,
    "9-12 PM": 0,
    "12-3 PM": 0,
    "3-6 PM": 0,
    "6-9 PM": 0,
    "9-12 AM": 0,
  },
};

const HOUR_COLORS: Record<string, string> = {
  "6-9 AM": "#34d399",
  "9-12 PM": "#34d399",
  "12-3 PM": "#fbbf24",
  "3-6 PM": "#38bdf8",
  "6-9 PM": "#fbbf24",
  "9-12 AM": "#fb7185",
};

// ── Component ───────────────────────────────────────────────────────────────
export default function AnalyticsPage() {
  const [timeRange, setTimeRange] = useState<"week" | "month" | "3months">(
    "week",
  );
  const [data, setData] = useState<AnalyticsSummary>(FALLBACK);
  const [loading, setLoading] = useState(true);
  const [apiError, setApiError] = useState<string | null>(null);

  const load = useCallback(() => {
    setLoading(true);
    getAnalyticsSummary(timeRange)
      .then((summary) => {
        setData(summary);
        setApiError(null);
      })
      .catch((err) => {
        console.warn("Analytics API error:", err.message);
        setApiError("We couldn’t load your insights. Please try again.");
      })
      .finally(() => setLoading(false));
  }, [timeRange]);
  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);
  useDataRefresh(load);

  // ── Derive chart datasets from API data ───────────────────────────────────
  const trendLabels = data.execution_trend.map((p) => p.label);
  const plannedData = data.execution_trend.map((p) => p.planned_mins);
  const completedData = data.execution_trend.map((p) => p.completed_mins);
  const successRateData = data.execution_trend.map((p) => p.success_rate);

  const hourLabels = Object.keys(data.success_by_hour);
  const hourData = Object.values(data.success_by_hour);
  const hourColors = hourLabels.map((h) => HOUR_COLORS[h] ?? "#94a3b8");

  const catLabels = Object.keys(data.failure_by_category);
  const catData = Object.values(data.failure_by_category);

  const reasonLabels = Object.keys(data.failure_by_reason).map((r) =>
    r.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()),
  );
  const reasonData = Object.values(data.failure_by_reason);
  const REASON_COLORS = [
    "#0f172a",
    "#38bdf8",
    "#fbbf24",
    "#a78bfa",
    "#e2e8f0",
    "#34d399",
    "#fb7185",
  ];

  // ── Stat cards ────────────────────────────────────────────────────────────
  const stats = [
    {
      label: "Overall success rate",
      value: `${data.success_rate}%`,
      change: "based on completed tasks",
      positive: true,
    },
    {
      label: "Total tasks",
      value: String(data.total_tasks),
      change: `in this ${timeRange}`,
      positive: true,
    },
    {
      label: "Category to revisit",
      value: data.most_failed_category,
      change: "highest failure count",
      positive: false,
    },
    {
      label: "Best time of day",
      value: data.best_time_of_day,
      change: "highest success rate",
      positive: true,
    },
    {
      label: "Avg interruptions",
      value: String(data.avg_interruptions),
      change: "per task",
      positive: false,
    },
    {
      label: "Avg importance",
      value: String(data.avg_importance),
      change: "out of 5",
      positive: true,
    },
  ];

  // ── Chart configs ──────────────────────────────────────────────────────────
  const executionTrendOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: "top" as const,
        labels: {
          usePointStyle: true,
          pointStyle: "circle" as const,
          padding: 20,
          font: { size: 12 },
        },
      },
      tooltip: tooltipStyle,
    },
    scales: {
      x: {
        grid: { display: false },
        ticks: { font: { size: 12 }, color: "#94a3b8" },
      },
      y: {
        beginAtZero: true,
        grid: { color: "#f1f5f9" },
        ticks: { font: { size: 12 }, color: "#94a3b8" },
      },
    },
  };

  const successRateOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        ...tooltipStyle,
        callbacks: {
          label: (ctx: { parsed: { y: number | null } }) =>
            `${ctx.parsed.y ?? 0}% success rate`,
        },
      },
    },
    scales: {
      x: {
        grid: { display: false },
        ticks: { font: { size: 12 }, color: "#94a3b8" },
      },
      y: {
        min: 0,
        max: 100,
        grid: { color: "#f1f5f9" },
        ticks: {
          font: { size: 12 },
          color: "#94a3b8",
          callback: (v: number | string) => `${v}%`,
        },
      },
    },
  };

  const timeOfDayOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        ...tooltipStyle,
        callbacks: {
          label: (ctx: { parsed: { y: number | null } }) =>
            `${ctx.parsed.y ?? 0}% success rate`,
        },
      },
    },
    scales: {
      x: {
        grid: { display: false },
        ticks: { font: { size: 12 }, color: "#94a3b8" },
      },
      y: {
        min: 0,
        max: 100,
        grid: { color: "#f1f5f9" },
        ticks: {
          font: { size: 12 },
          color: "#94a3b8",
          callback: (v: number | string) => `${v}%`,
        },
      },
    },
  };

  const failureByCategoryOptions = {
    responsive: true,
    maintainAspectRatio: false,
    indexAxis: "y" as const,
    plugins: { legend: { display: false }, tooltip: tooltipStyle },
    scales: {
      x: {
        grid: { color: "#f1f5f9" },
        ticks: { font: { size: 12 }, color: "#94a3b8" },
      },
      y: {
        grid: { display: false },
        ticks: { font: { size: 12 }, color: "#64748b" },
      },
    },
  };

  const failureReasonsOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: "bottom" as const,
        labels: {
          usePointStyle: true,
          pointStyle: "circle" as const,
          padding: 14,
          font: { size: 11 },
        },
      },
      tooltip: {
        ...tooltipStyle,
        callbacks: {
          label: (ctx: { label: string; parsed: number | null }) =>
            ` ${ctx.label}: ${ctx.parsed ?? 0}`,
        },
      },
    },
    cutout: "65%",
  };

  if (loading)
    return (
      <p role="status" className="panel">
        Loading your insights…
      </p>
    );
  if (apiError)
    return (
      <section role="alert" className="panel">
        <h1 className="text-xl font-semibold">Insights unavailable</h1>
        <p className="my-3">{apiError}</p>
        <button className="btn-secondary" onClick={load}>
          Try again
        </button>
      </section>
    );
  if (data.total_tasks === 0)
    return (
      <section className="panel text-center">
        <h1 className="text-2xl font-bold">Your story starts with one plan</h1>
        <p className="my-4 text-slate-500">
          There are no plans in this period yet. Record a few outcomes to
          discover what works for you.
        </p>
        <div className="mb-4 flex justify-center gap-2">
          {(["week", "month", "3months"] as const).map((r) => (
            <button
              key={r}
              className="btn-secondary"
              onClick={() => setTimeRange(r)}
            >
              {r === "3months" ? "3 months" : r}
            </button>
          ))}
        </div>
        <Link className="btn-primary" href="/dashboard/habits">
          Plan something small
        </Link>
      </section>
    );

  return (
    <div className="space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <div className="text-xs text-slate-500">Analytics</div>
          <h1 className="text-xl font-bold">What works for you</h1>
        </div>
        <div className="flex items-center gap-3">
          {apiError && (
            <div className="px-3 py-1.5 rounded-lg bg-amber-50 border border-amber-100 text-xs text-amber-700">
              Insights unavailable
            </div>
          )}
          <div className="flex rounded-xl border border-slate-200 overflow-hidden">
            {(["week", "month", "3months"] as const).map((range) => (
              <button
                key={range}
                onClick={() => setTimeRange(range)}
                className={`px-3 py-1.5 text-xs font-medium transition-colors border-r border-slate-200 last:border-r-0 ${
                  timeRange === range
                    ? "bg-slate-900 text-white"
                    : "bg-white text-slate-500 hover:text-slate-700"
                }`}
              >
                {range === "week"
                  ? "Week"
                  : range === "month"
                    ? "Month"
                    : "3 months"}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="panel !bg-emerald-50">
        <p className="font-semibold">One thing to try next</p>
        <p className="mt-2 text-sm text-slate-700">
          {data.best_time_of_day && data.best_time_of_day !== "—"
            ? `Your recorded outcomes have been strongest around ${data.best_time_of_day}. Try one important plan in that window and see how it feels.`
            : "Keep your next plan short and record how it went. A few outcomes are more useful than a packed schedule."}
        </p>
        <p className="mt-2 text-xs text-slate-600">
          Based on your recorded history, not a guarantee. Small samples can be
          misleading.
        </p>
        <Link href="/dashboard/scheduler" className="btn-secondary mt-3">
          Find a time
        </Link>
      </div>
      {/* Stats Row */}
      <div className="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
        {stats.map((stat) => (
          <div
            key={stat.label}
            className="bg-white rounded-xl border border-slate-200 p-3"
          >
            <div className="text-xs text-slate-500 leading-tight">
              {stat.label}
            </div>
            <div
              className={`text-lg font-bold mt-0.5 ${loading ? "animate-pulse text-slate-300" : ""}`}
            >
              {loading ? "—" : stat.value}
            </div>
            <div
              className={`text-xs mt-0.5 ${stat.positive ? "text-emerald-600" : "text-slate-500"}`}
            >
              {stat.change}
            </div>
          </div>
        ))}
      </div>

      {/* Row 1: Execution Trend + Success Rate + Time of Day */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">Execution trend</div>
          <div className="text-xs text-slate-500 mb-2">
            Planned vs completed minutes
          </div>
          <div className="h-[155px]">
            <Line
              options={executionTrendOptions}
              data={{
                labels: trendLabels,
                datasets: [
                  {
                    label: "Planned (min)",
                    data: plannedData,
                    borderColor: "#0f172a",
                    backgroundColor: "rgba(15,23,42,0.05)",
                    fill: true,
                    borderWidth: 2,
                    tension: 0.35,
                  },
                  {
                    label: "Completed (min)",
                    data: completedData,
                    borderColor: "#34d399",
                    backgroundColor: "rgba(52,211,153,0.05)",
                    fill: true,
                    borderWidth: 2,
                    tension: 0.35,
                  },
                ],
              }}
            />
          </div>
        </div>

        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">Success rate over time</div>
          <div className="text-xs text-slate-500 mb-2">
            % of tasks completed successfully
          </div>
          <div className="h-[155px]">
            <Line
              options={successRateOptions}
              data={{
                labels: trendLabels,
                datasets: [
                  {
                    label: "Success rate %",
                    data: successRateData,
                    borderColor: "#34d399",
                    backgroundColor: "rgba(52,211,153,0.1)",
                    fill: true,
                    borderWidth: 2,
                    tension: 0.35,
                    pointBackgroundColor: "#34d399",
                  },
                ],
              }}
            />
          </div>
        </div>

        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">
            Performance by time of day
          </div>
          <div className="text-xs text-slate-500 mb-2">
            When you&apos;re most likely to succeed
          </div>
          <div className="h-[155px]">
            <Bar
              options={timeOfDayOptions}
              data={{
                labels: hourLabels,
                datasets: [
                  {
                    label: "Success rate %",
                    data: hourData,
                    backgroundColor: hourColors,
                    borderWidth: 0,
                    borderRadius: 6,
                  },
                ],
              }}
            />
          </div>
        </div>
      </div>

      {/* Row 2: Planning obstacles by Category + Why tasks fail + Key Insights */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">
            Planning obstacles by category
          </div>
          <div className="text-xs text-slate-500 mb-2">
            Which types of tasks fail most
          </div>
          <div className="h-[155px]">
            {catLabels.length > 0 ? (
              <Bar
                options={failureByCategoryOptions}
                data={{
                  labels: catLabels,
                  datasets: [
                    {
                      label: "Failed tasks",
                      data: catData,
                      backgroundColor: [
                        "#38bdf8",
                        "#a78bfa",
                        "#34d399",
                        "#94a3b8",
                        "#fbbf24",
                        "#fb7185",
                      ],
                      borderWidth: 0,
                      borderRadius: 6,
                    },
                  ],
                }}
              />
            ) : (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">
                {loading ? "Loading…" : "No failure data yet"}
              </div>
            )}
          </div>
        </div>

        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">Why tasks fail</div>
          <div className="text-xs text-slate-500 mb-2">
            Most common failure reasons
          </div>
          <div className="h-[155px]">
            {reasonLabels.length > 0 ? (
              <Doughnut
                options={failureReasonsOptions}
                data={{
                  labels: reasonLabels,
                  datasets: [
                    {
                      data: reasonData,
                      backgroundColor: REASON_COLORS.slice(
                        0,
                        reasonLabels.length,
                      ),
                      borderWidth: 0,
                      hoverOffset: 6,
                    },
                  ],
                }}
              />
            ) : (
              <div className="h-full flex items-center justify-center text-sm text-slate-400">
                {loading ? "Loading…" : "No failure data yet"}
              </div>
            )}
          </div>
        </div>

        <div className="bg-white rounded-xl border border-slate-200 p-3">
          <div className="text-sm font-semibold">Key insights</div>
          <div className="text-xs text-slate-500 mb-2">
            Observations from your data
          </div>

          <div className="space-y-2">
            {data.best_time_of_day !== "—" && (
              <div className="flex items-start gap-2 p-2 rounded-lg bg-emerald-50 border border-emerald-100">
                <div className="mt-1 h-1.5 w-1.5 rounded-full bg-emerald-400 shrink-0" />
                <div>
                  <div className="text-xs font-medium text-emerald-900">
                    Best: {data.best_time_of_day}
                  </div>
                  <div className="text-xs text-emerald-700">
                    {data.success_by_hour[data.best_time_of_day] ?? 0}% success
                    rate
                  </div>
                </div>
              </div>
            )}

            {data.most_failed_category !== "—" &&
              data.most_failed_category !== "N/A" && (
                <div className="flex items-start gap-2 p-2 rounded-lg bg-rose-50 border border-rose-100">
                  <div className="mt-1 h-1.5 w-1.5 rounded-full bg-rose-400 shrink-0" />
                  <div>
                    <div className="text-xs font-medium text-rose-900">
                      Most failures: {data.most_failed_category}
                    </div>
                    <div className="text-xs text-rose-700">
                      {data.failure_by_category[data.most_failed_category] ?? 0}{" "}
                      failed tasks
                    </div>
                  </div>
                </div>
              )}

            {data.avg_interruptions > 1.5 && (
              <div className="flex items-start gap-2 p-2 rounded-lg bg-amber-50 border border-amber-100">
                <div className="mt-1 h-1.5 w-1.5 rounded-full bg-amber-400 shrink-0" />
                <div>
                  <div className="text-xs font-medium text-amber-900">
                    High interruptions: {data.avg_interruptions}/task
                  </div>
                  <div className="text-xs text-amber-700">
                    Try scheduling focus blocks
                  </div>
                </div>
              </div>
            )}

            {data.success_rate > 0 && (
              <div className="flex items-start gap-2 p-2 rounded-lg bg-sky-50 border border-sky-100">
                <div className="mt-1 h-1.5 w-1.5 rounded-full bg-sky-400 shrink-0" />
                <div>
                  <div className="text-xs font-medium text-sky-900">
                    Success rate: {data.success_rate}%
                  </div>
                  <div className="text-xs text-sky-700">
                    {data.total_tasks} tasks tracked
                  </div>
                </div>
              </div>
            )}

            {data.total_tasks === 0 && !loading && (
              <div className="flex items-start gap-2 p-2 rounded-lg bg-slate-50 border border-slate-100">
                <div className="mt-1 h-1.5 w-1.5 rounded-full bg-slate-300 shrink-0" />
                <div>
                  <div className="text-xs font-medium text-slate-600">
                    No data yet
                  </div>
                  <div className="text-xs text-slate-500">
                    Add tasks in the Habits tab
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
