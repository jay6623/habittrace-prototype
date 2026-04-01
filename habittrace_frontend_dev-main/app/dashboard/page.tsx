"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import ExecutionTrendChart from "@/components/charts/execution-trend";
import FailurePatternChart from "@/components/charts/failure-pattern";
import CoachChat from "@/components/coach-chat";
import { useAuth } from "@/app/providers";
import { getAnalyticsSummary, getTasks, type AnalyticsSummary, type Task } from "@/lib/api";

// 시간대별 인사말
function getGreeting(name: string): string {
  const hour = new Date().getHours();
  if (hour < 12) return `Good morning, ${name} 👋`;
  if (hour < 18) return `Good afternoon, ${name} 👋`;
  return `Good evening, ${name} 👋`;
}

// 실패 이유 레이블 한글화 (선택사항 — 영어로 표시해도 OK)
function formatReason(key: string): string {
  const map: Record<string, string> = {
    low_energy:        "Low energy",
    low_focus:         "Low focus",
    start_delay:       "Started late",
    interruptions:     "Interruptions",
    time_underestimate:"Underestimated time",
    schedule_conflict: "Schedule conflict",
    unexpected_event:  "Unexpected event",
    other:             "Other",
  };
  return map[key] ?? key.replace(/_/g, " ");
}

export default function DashboardPage() {
  const { user, displayName } = useAuth();
  const router = useRouter();

  const [analytics, setAnalytics] = useState<AnalyticsSummary | null>(null);
  const [todayTasks, setTodayTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);
  const [chatOpen, setChatOpen] = useState(false);

  useEffect(() => {
    const today = new Date().toISOString().split("T")[0];

    Promise.all([
      getAnalyticsSummary("week"),
      getTasks(today),
    ])
      .then(([summary, tasks]) => {
        setAnalytics(summary);
        setTodayTasks(tasks);
      })
      .catch((err) => console.warn("Dashboard data fetch failed:", err))
      .finally(() => setLoading(false));
  }, []);

  // ── 오늘 요약 통계 ─────────────────────────────────────────────────────────
  const totalToday = todayTasks.length;
  const successToday = todayTasks.filter((t) => t.task_status === "success").length;
  const pendingToday = todayTasks.filter((t) => t.task_status === "pending").length;
  const successRateToday =
    totalToday > 0 ? Math.round((successToday / totalToday) * 100) : null;

  // ── 차트 데이터 ────────────────────────────────────────────────────────────
  const trendLabels = analytics?.execution_trend.map((p) => p.label) ?? ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
  const trendPlanned = analytics?.execution_trend.map((p) => p.planned_mins) ?? [0,0,0,0,0,0,0];
  const trendCompleted = analytics?.execution_trend.map((p) => p.completed_mins) ?? [0,0,0,0,0,0,0];

  const failureEntries = analytics
    ? Object.entries(analytics.failure_by_reason).sort((a, b) => b[1] - a[1])
    : [];
  const failureLabels = failureEntries.map(([k]) => formatReason(k));
  const failureData = failureEntries.map(([, v]) => v);

  return (
    <div className="space-y-5">
      {/* Greeting Banner */}
      <section className="bg-white rounded-2xl border border-slate-200 p-5 flex items-center gap-4">
        <div className="h-12 w-12 rounded-full bg-slate-900 flex items-center justify-center text-white font-bold text-lg shrink-0">
          {displayName.charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-lg">
            {getGreeting(displayName)}
          </div>
          <div className="text-sm text-slate-500">
            {totalToday > 0
              ? `${totalToday} tasks planned today · ${successToday} done · ${pendingToday} remaining`
              : "No tasks planned yet today — add one in the Habits tab."}
          </div>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => router.push("/dashboard/habits")}
            className="px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm"
          >
            Add plan
          </button>
          <button
            onClick={() => setChatOpen(true)}
            className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm"
          >
            Ask AI
          </button>
        </div>
      </section>

      {/* Today stats row */}
      {(totalToday > 0 || !loading) && (
        <section className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="bg-white rounded-2xl border border-slate-200 p-4">
            <div className="text-xs text-slate-500">Today&apos;s success rate</div>
            <div className="text-2xl font-bold mt-1">
              {successRateToday !== null ? `${successRateToday}%` : "—"}
            </div>
            {successRateToday !== null && (
              <div className="mt-2 h-2 rounded-full bg-slate-100 overflow-hidden">
                <div className="h-full bg-emerald-400 rounded-full" style={{ width: `${successRateToday}%` }} />
              </div>
            )}
          </div>
          <div className="bg-white rounded-2xl border border-slate-200 p-4">
            <div className="text-xs text-slate-500">Tasks today</div>
            <div className="flex items-baseline gap-1 mt-1">
              <span className="text-2xl font-bold text-emerald-600">{successToday}</span>
              <span className="text-sm text-slate-500">/ {totalToday}</span>
            </div>
            <div className="text-xs text-slate-500 mt-1">{pendingToday} pending</div>
          </div>
          <div className="bg-white rounded-2xl border border-slate-200 p-4">
            <div className="text-xs text-slate-500">This week&apos;s success rate</div>
            <div className="text-2xl font-bold mt-1">
              {analytics ? `${analytics.success_rate}%` : "—"}
            </div>
            <div className="text-xs text-slate-500 mt-1">{analytics?.total_tasks ?? 0} tasks tracked</div>
          </div>
          <div className="bg-white rounded-2xl border border-slate-200 p-4">
            <div className="text-xs text-slate-500">Best time of day</div>
            <div className="text-2xl font-bold mt-1">{analytics?.best_time_of_day ?? "—"}</div>
            <div className="text-xs text-slate-500 mt-1">highest success rate</div>
          </div>
        </section>
      )}

      {/* Charts Row */}
      <section className="grid grid-cols-1 xl:grid-cols-2 gap-5">
        {/* Execution Trend */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="flex items-start justify-between gap-3 mb-4">
            <div>
              <div className="font-semibold">Execution trend</div>
              <div className="text-sm text-slate-500">Planned vs completed this week</div>
            </div>
          </div>
          {loading ? (
            <div className="h-[240px] flex items-center justify-center text-sm text-slate-400">
              Loading…
            </div>
          ) : (
            <ExecutionTrendChart
              labels={trendLabels}
              planned={trendPlanned}
              completed={trendCompleted}
            />
          )}
        </div>

        {/* Failure Patterns */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="flex items-start justify-between gap-3 mb-4">
            <div>
              <div className="font-semibold">Failure pattern mix</div>
              <div className="text-sm text-slate-500">Where plans usually break</div>
            </div>
          </div>
          {loading ? (
            <div className="h-[240px] flex items-center justify-center text-sm text-slate-400">
              Loading…
            </div>
          ) : failureLabels.length > 0 ? (
            <FailurePatternChart labels={failureLabels} data={failureData} />
          ) : (
            <div className="h-[240px] flex items-center justify-center text-sm text-slate-400">
              No failure data yet — complete some tasks to see patterns.
            </div>
          )}
        </div>
      </section>

      {/* Lower Row */}
      <section className="grid grid-cols-1 xl:grid-cols-2 gap-5">
        {/* Weekly summary */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="flex items-center justify-between">
            <div>
              <div className="font-semibold">Weekly summary</div>
              <div className="text-sm text-slate-500">Your performance this week</div>
            </div>
          </div>

          <div className="mt-4 space-y-3">
            {analytics ? (
              <>
                <div className="flex items-center justify-between py-2 border-b border-slate-100">
                  <span className="text-sm text-slate-600">Total tasks</span>
                  <span className="text-sm font-semibold">{analytics.total_tasks}</span>
                </div>
                <div className="flex items-center justify-between py-2 border-b border-slate-100">
                  <span className="text-sm text-slate-600">Success rate</span>
                  <span className="text-sm font-semibold text-emerald-600">{analytics.success_rate}%</span>
                </div>
                <div className="flex items-center justify-between py-2 border-b border-slate-100">
                  <span className="text-sm text-slate-600">Most failed category</span>
                  <span className="text-sm font-semibold text-rose-600">{analytics.most_failed_category}</span>
                </div>
                <div className="flex items-center justify-between py-2 border-b border-slate-100">
                  <span className="text-sm text-slate-600">Avg interruptions</span>
                  <span className="text-sm font-semibold">{analytics.avg_interruptions} per task</span>
                </div>
                <div className="flex items-center justify-between py-2">
                  <span className="text-sm text-slate-600">Total planned time</span>
                  <span className="text-sm font-semibold">{analytics.total_planned_minutes} min</span>
                </div>
              </>
            ) : (
              <div className="py-8 text-center text-sm text-slate-400">
                {loading ? "Loading…" : "No data yet. Start tracking tasks!"}
              </div>
            )}
          </div>
        </div>

        {/* Coach Chat */}
        <CoachChat />
      </section>

      {/* AI Coach Modal */}
      {chatOpen && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
          onClick={(e) => { if (e.target === e.currentTarget) setChatOpen(false); }}
        >
          <div className="w-full max-w-2xl h-[680px] flex flex-col">
            <div className="flex items-center justify-between mb-3">
              <span className="text-white font-semibold text-sm">AI Coach</span>
              <button
                onClick={() => setChatOpen(false)}
                className="text-white/70 hover:text-white text-xl leading-none"
              >
                ✕
              </button>
            </div>
            <div className="flex-1 min-h-0">
              <CoachChat />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
