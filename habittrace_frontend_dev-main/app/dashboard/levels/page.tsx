"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import {
  BarElement,
  CategoryScale,
  Chart as ChartJS,
  LinearScale,
  Tooltip,
} from "chart.js";
import { Bar } from "react-chartjs-2";
import { getXpSummary, type XpOutcome, type XpSummary } from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip);

const OUTCOME_LABELS: Record<XpOutcome, { label: string; tone: string }> = {
  completed: { label: "Completed", tone: "bg-emerald-50 text-emerald-700" },
  partial: { label: "Partly done", tone: "bg-amber-50 text-amber-700" },
  not_started: { label: "Not started", tone: "bg-slate-100 text-slate-600" },
  abandoned: { label: "Stopped", tone: "bg-slate-100 text-slate-600" },
  failed: { label: "Not completed", tone: "bg-slate-100 text-slate-600" },
};

function localDate(iso: string): Date {
  // Plan dates are calendar days; parse them as local midnight, not UTC.
  return new Date(`${iso}T00:00:00`);
}

function shortDay(iso: string): string {
  return localDate(iso).toLocaleDateString(undefined, { weekday: "short" });
}

function longDay(iso: string): string {
  return localDate(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function outcomeDetail(outcome: XpOutcome, ratio: number): string {
  if (outcome === "partial") return `${Math.round(ratio * 100)}% done`;
  return OUTCOME_LABELS[outcome].label;
}

export default function LevelsPage() {
  const [data, setData] = useState<XpSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    getXpSummary()
      .then((summary) => {
        setData(summary);
        setError(null);
      })
      .catch((err: Error) => {
        console.warn("XP summary API error:", err.message);
        setError("We couldn’t load your level. Please try again.");
      })
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => {
    const timer = setTimeout(load, 0);
    return () => clearTimeout(timer);
  }, [load]);
  useDataRefresh(load);

  if (loading)
    return (
      <p role="status" className="panel">
        Loading your level…
      </p>
    );
  if (error || !data)
    return (
      <section role="alert" className="panel">
        <h1 className="text-xl font-semibold">Levels unavailable</h1>
        <p className="my-3">{error ?? "Something went wrong."}</p>
        <button
          className="btn-secondary"
          onClick={() => {
            setLoading(true);
            load();
          }}
        >
          Try again
        </button>
      </section>
    );

  const percent = Math.round(data.progress * 100);
  const chartData = {
    labels: data.daily_xp.map((d) => shortDay(d.date)),
    datasets: [
      {
        label: "XP",
        data: data.daily_xp.map((d) => d.xp),
        backgroundColor: data.daily_xp.map((d, i) =>
          i === data.daily_xp.length - 1 ? "#059669" : "#a7f3d0",
        ),
        borderRadius: 6,
        maxBarThickness: 28,
      },
    ],
  };
  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: "#0f172a",
        padding: 10,
        cornerRadius: 10,
        displayColors: false,
        callbacks: {
          title: (items: { dataIndex: number }[]) =>
            longDay(data.daily_xp[items[0]?.dataIndex ?? 0]?.date ?? ""),
          label: (ctx: { parsed: { y: number | null } }) => ` ${ctx.parsed.y ?? 0} XP`,
        },
      },
    },
    scales: {
      x: { grid: { display: false }, ticks: { font: { size: 11 } } },
      y: {
        beginAtZero: true,
        ticks: { precision: 0, font: { size: 11 } },
        grid: { color: "#f1f5f9" },
      },
    },
  };

  return (
    <div className="space-y-3">
      <div>
        <div className="text-xs text-slate-500">Levels</div>
        <h1 className="text-xl font-bold">Your progress</h1>
      </div>

      <section className="overflow-hidden rounded-2xl border border-emerald-200 bg-gradient-to-br from-emerald-50 via-white to-lime-50 p-4 shadow-sm sm:p-5">
        <div className="flex flex-wrap items-center gap-4">
          <div
            className="grid h-20 w-20 shrink-0 place-items-center rounded-2xl bg-slate-950 text-white"
            aria-hidden="true"
          >
            <div className="text-center leading-none">
              <div className="text-[10px] font-semibold uppercase tracking-widest text-emerald-300">
                Level
              </div>
              <div className="mt-1 text-3xl font-bold">{data.level}</div>
            </div>
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-xs font-bold uppercase tracking-[0.14em] text-emerald-700">
              Level {data.level}
            </div>
            <h2 className="text-2xl font-bold text-slate-950">{data.level_title}</h2>
            <p className="mt-1 text-sm text-slate-600">
              {data.total_xp.toLocaleString()} XP total ·{" "}
              {data.xp_to_next_level.toLocaleString()} XP to level {data.level + 1}
            </p>
          </div>
        </div>
        <div className="mt-4">
          <div
            role="progressbar"
            aria-label={`Progress to level ${data.level + 1}`}
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={percent}
            className="h-3 overflow-hidden rounded-full bg-emerald-100"
          >
            <div
              className="h-full rounded-full bg-emerald-600 transition-[width] duration-500"
              style={{ width: `${percent}%` }}
            />
          </div>
          <div className="mt-1.5 flex justify-between text-xs text-slate-500">
            <span>{data.level_start_xp.toLocaleString()} XP</span>
            <span>
              {data.xp_into_level} / {data.next_level_xp - data.level_start_xp} XP this level
            </span>
            <span>{data.next_level_xp.toLocaleString()} XP</span>
          </div>
        </div>
      </section>

      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4" aria-label="XP stats">
        {[
          { label: "Total XP", value: data.total_xp },
          { label: "XP last 7 days", value: data.xp_this_week },
          { label: "Outcomes logged", value: data.outcomes_logged },
          { label: "Plans completed", value: data.plans_completed },
        ].map((stat) => (
          <div key={stat.label} className="rounded-2xl border border-slate-200 bg-white p-4">
            <div className="text-xs text-slate-500">{stat.label}</div>
            <div className="mt-1 text-2xl font-bold">{stat.value.toLocaleString()}</div>
          </div>
        ))}
      </section>

      {data.outcomes_logged === 0 ? (
        <section className="panel text-center">
          <h2 className="text-lg font-bold">Earn your first XP</h2>
          <p className="my-3 text-slate-500">
            Record how a plan went — even if it didn’t happen — and XP will start adding up.
          </p>
          <Link className="btn-primary" href="/dashboard/habits">
            Go to my plans
          </Link>
        </section>
      ) : (
        <div className="grid gap-3 lg:grid-cols-5">
          <section className="flex flex-col rounded-2xl border border-slate-200 bg-white p-4 lg:col-span-3">
            <h2 className="font-semibold">XP over the last 14 days</h2>
            {/* Fills the row on desktop so it lines up with the Recent XP list. */}
            <div className="relative mt-3 min-h-56 flex-1">
              <Bar data={chartData} options={chartOptions} />
            </div>
          </section>
          <section className="rounded-2xl border border-slate-200 bg-white p-4 lg:col-span-2">
            <h2 className="font-semibold">Recent XP</h2>
            <ul className="mt-2 divide-y divide-slate-100">
              {data.recent.map((event) => (
                <li key={event.task_id} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium">{event.title}</div>
                    <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-xs text-slate-500">
                      <span>{longDay(event.planned_date)}</span>
                      <span aria-hidden="true">·</span>
                      <span
                        className={`rounded-full px-2 py-0.5 font-medium ${OUTCOME_LABELS[event.outcome].tone}`}
                      >
                        {outcomeDetail(event.outcome, event.completion_ratio)}
                      </span>
                    </div>
                  </div>
                  <div className="shrink-0 text-right">
                    <div className="text-sm font-bold text-emerald-700">+{event.xp} XP</div>
                    <div className="text-[11px] text-slate-400">
                      {event.logging_xp} log + {event.completion_xp} done
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        </div>
      )}

      <section className="rounded-2xl border border-slate-200 bg-white p-4">
        <h2 className="font-semibold">How XP works</h2>
        <ul className="mt-2 space-y-1.5 text-sm text-slate-600">
          <li>
            <span className="font-medium text-slate-800">+2 XP</span> for recording any
            outcome, even “not started” — honest records help the app learn what works for
            you.
          </li>
          <li>
            <span className="font-medium text-slate-800">10 XP + 2 × importance</span> for a
            completed plan, plus 1 XP for every 15 planned minutes (up to +8).
          </li>
          <li>Partly done plans earn the same share of that XP as the part you finished.</li>
          <li>Each new level needs 100 XP more than the last one.</li>
        </ul>
      </section>
    </div>
  );
}
