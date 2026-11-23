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
import {
  getXpSummary,
  type Achievement,
  type Milestone,
  type XpOutcome,
  type XpSummary,
} from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";

ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip);

// ── Palette ─────────────────────────────────────────────────────────────────
// The Levels page gets its own, more playful palette so rewards stand apart
// from the calm emerald/slate used for planning. Class names are written out
// in full so Tailwind can see them.

/** Per-badge colors: an unlocked tile, card tint, accent text and progress fill. */
type Theme = { tile: string; card: string; text: string; fill: string };

const BADGE_THEMES: Record<string, Theme> = {
  first_step: {
    tile: "from-sky-400 to-blue-600",
    card: "border-sky-200 bg-sky-50/70",
    text: "text-sky-700",
    fill: "bg-sky-500",
  },
  early_bird: {
    tile: "from-amber-300 to-orange-500",
    card: "border-amber-200 bg-amber-50/70",
    text: "text-amber-700",
    fill: "bg-amber-500",
  },
  night_owl: {
    tile: "from-indigo-500 to-violet-800",
    card: "border-indigo-200 bg-indigo-50/70",
    text: "text-indigo-700",
    fill: "bg-indigo-500",
  },
  deep_work: {
    tile: "from-violet-500 to-fuchsia-600",
    card: "border-violet-200 bg-violet-50/70",
    text: "text-violet-700",
    fill: "bg-violet-500",
  },
  perfect_day: {
    tile: "from-emerald-400 to-teal-600",
    card: "border-emerald-200 bg-emerald-50/70",
    text: "text-emerald-700",
    fill: "bg-emerald-500",
  },
  explorer: {
    tile: "from-teal-300 to-cyan-600",
    card: "border-cyan-200 bg-cyan-50/70",
    text: "text-cyan-700",
    fill: "bg-cyan-500",
  },
  team_player: {
    tile: "from-rose-400 to-pink-600",
    card: "border-rose-200 bg-rose-50/70",
    text: "text-rose-700",
    fill: "bg-rose-500",
  },
  honest_tracker: {
    tile: "from-lime-400 to-green-600",
    card: "border-lime-200 bg-lime-50/70",
    text: "text-lime-700",
    fill: "bg-lime-500",
  },
};

const STREAK_THEME: Theme = {
  tile: "from-orange-400 to-rose-500",
  card: "border-orange-200 bg-orange-50/70",
  text: "text-orange-700",
  fill: "bg-orange-500",
};

const MILESTONE_THEMES: Record<string, { fill: string; chip: string; text: string }> = {
  plans_completed: {
    fill: "bg-gradient-to-r from-emerald-400 to-teal-500",
    chip: "bg-emerald-500",
    text: "text-emerald-700",
  },
  focus_hours: {
    fill: "bg-gradient-to-r from-sky-400 to-blue-500",
    chip: "bg-sky-500",
    text: "text-sky-700",
  },
  outcomes_logged: {
    fill: "bg-gradient-to-r from-violet-400 to-fuchsia-500",
    chip: "bg-violet-500",
    text: "text-violet-700",
  },
};

const FALLBACK_MILESTONE = MILESTONE_THEMES.plans_completed;

const OUTCOME_LABELS: Record<XpOutcome, { label: string; tone: string }> = {
  completed: { label: "Completed", tone: "bg-emerald-50 text-emerald-700" },
  partial: { label: "Partly done", tone: "bg-amber-50 text-amber-700" },
  not_started: { label: "Not started", tone: "bg-slate-100 text-slate-600" },
  abandoned: { label: "Stopped", tone: "bg-slate-100 text-slate-600" },
  failed: { label: "Not completed", tone: "bg-slate-100 text-slate-600" },
};

function badgeTheme(badge: Achievement): Theme {
  return badge.kind === "streak" ? STREAK_THEME : (BADGE_THEMES[badge.id] ?? BADGE_THEMES.first_step);
}

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

function days(count: number): string {
  return `${count} ${count === 1 ? "day" : "days"}`;
}

function ProgressBar({
  value,
  max,
  label,
  fill,
  track = "bg-slate-100",
  height = "h-1.5",
}: {
  value: number;
  max: number;
  label: string;
  fill: string;
  track?: string;
  height?: string;
}) {
  const percent = max > 0 ? Math.min(100, Math.round((value / max) * 100)) : 0;
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={percent}
      className={`${height} overflow-hidden rounded-full ${track}`}
    >
      <div
        className={`h-full rounded-full ${fill} transition-[width] duration-500`}
        style={{ width: `${percent}%` }}
      />
    </div>
  );
}

// ── Sections ────────────────────────────────────────────────────────────────

function LevelCard({ data }: { data: XpSummary }) {
  return (
    <section className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-violet-600 via-indigo-600 to-fuchsia-600 p-4 text-white shadow-lg shadow-violet-200 sm:p-5 lg:col-span-2">
      {/* Soft light spots for depth; purely decorative. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-10 -top-16 h-48 w-48 rounded-full bg-fuchsia-400/30 blur-2xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-20 left-1/3 h-40 w-40 rounded-full bg-sky-400/20 blur-2xl"
      />
      <div className="relative flex flex-wrap items-center gap-4">
        <div
          className="grid h-20 w-20 shrink-0 place-items-center rounded-2xl bg-white/15 ring-1 ring-white/30 backdrop-blur"
          aria-hidden="true"
        >
          <div className="text-center leading-none">
            <div className="text-[10px] font-semibold uppercase tracking-widest text-amber-200">
              Level
            </div>
            <div className="mt-1 text-3xl font-bold">{data.level}</div>
          </div>
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-xs font-bold uppercase tracking-[0.14em] text-amber-200">
            Level {data.level}
          </div>
          <h2 className="text-2xl font-bold">{data.level_title}</h2>
          <p className="mt-1 text-sm text-violet-100">
            {data.total_xp.toLocaleString()} XP total ·{" "}
            {data.xp_to_next_level.toLocaleString()} XP to level {data.level + 1}
          </p>
        </div>
      </div>
      <div className="relative mt-4">
        <ProgressBar
          value={data.xp_into_level}
          max={data.next_level_xp - data.level_start_xp}
          label={`Progress to level ${data.level + 1}`}
          fill="bg-gradient-to-r from-amber-300 to-yellow-200 shadow-[0_0_12px_rgba(253,224,71,0.6)]"
          track="bg-white/20"
          height="h-3"
        />
        <div className="mt-1.5 flex justify-between text-xs text-violet-100">
          <span>{data.level_start_xp.toLocaleString()} XP</span>
          <span>
            {data.xp_into_level} / {data.next_level_xp - data.level_start_xp} XP this level
          </span>
          <span>{data.next_level_xp.toLocaleString()} XP</span>
        </div>
      </div>
    </section>
  );
}

function StreakCard({ streak }: { streak: XpSummary["streak"] }) {
  const message = streak.active_today
    ? "You completed a plan today. Nice!"
    : streak.current > 0
      ? "Complete a plan today to keep it going."
      : "Complete a plan today to start a streak.";
  return (
    <section className="relative flex flex-col justify-between overflow-hidden rounded-2xl bg-gradient-to-br from-amber-400 via-orange-500 to-rose-500 p-4 text-white shadow-lg shadow-orange-200 sm:p-5">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-8 -top-10 h-36 w-36 rounded-full bg-yellow-200/30 blur-2xl"
      />
      <div className="relative">
        <div className="text-xs font-bold uppercase tracking-[0.14em] text-yellow-100">
          Streak
        </div>
        <div className="mt-1 flex items-baseline gap-2">
          <span className="text-4xl font-bold">{streak.current}</span>
          <span className="text-sm font-medium text-orange-50">
            {streak.current === 1 ? "day" : "days"} in a row
          </span>
        </div>
        <p className="mt-2 text-sm text-orange-50">{message}</p>
      </div>
      <p className="relative mt-3 inline-flex w-fit rounded-full bg-white/20 px-2.5 py-1 text-xs font-medium">
        Longest streak: {days(streak.longest)}
      </p>
    </section>
  );
}

const STAT_STYLES = [
  { chip: "bg-violet-100 text-violet-700", icon: "✦" },
  { chip: "bg-sky-100 text-sky-700", icon: "↗" },
  { chip: "bg-amber-100 text-amber-700", icon: "★" },
  { chip: "bg-emerald-100 text-emerald-700", icon: "✓" },
];

function BadgeCard({ badge }: { badge: Achievement }) {
  const theme = badgeTheme(badge);
  return (
    <li
      className={`flex gap-3 rounded-2xl border p-3 transition-shadow ${
        badge.unlocked ? `${theme.card} shadow-sm` : "border-slate-200 bg-white"
      }`}
    >
      <div
        aria-hidden="true"
        className={`grid h-11 w-11 shrink-0 place-items-center rounded-xl text-lg ${
          badge.unlocked
            ? `bg-gradient-to-br ${theme.tile} text-white shadow-md`
            : "bg-slate-100 text-slate-300"
        }`}
      >
        {badge.icon}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-start justify-between gap-2">
          <h3 className={`text-sm font-semibold ${badge.unlocked ? "" : "text-slate-600"}`}>
            {badge.title}
            <span className="sr-only">{badge.unlocked ? " (unlocked)" : " (locked)"}</span>
          </h3>
          <span
            className={`shrink-0 text-xs font-semibold ${
              badge.unlocked ? theme.text : "text-slate-400"
            }`}
          >
            +{badge.bonus_xp} XP
          </span>
        </div>
        <p className="mt-0.5 text-xs text-slate-500">{badge.description}</p>
        {badge.unlocked && badge.unlocked_on ? (
          <p className={`mt-2 text-xs font-medium ${theme.text}`}>
            Unlocked {longDay(badge.unlocked_on)}
          </p>
        ) : (
          <div className="mt-2 flex items-center gap-2">
            <div className="flex-1">
              <ProgressBar
                value={badge.progress}
                max={badge.target}
                label={`${badge.title} progress`}
                fill={theme.fill}
              />
            </div>
            <span className="text-[11px] text-slate-500">
              {badge.progress}/{badge.target}
            </span>
          </div>
        )}
      </div>
    </li>
  );
}

function MilestoneRow({ milestone }: { milestone: Milestone }) {
  const theme = MILESTONE_THEMES[milestone.id] ?? FALLBACK_MILESTONE;
  const next = milestone.tiers.find((tier) => !tier.unlocked);
  const value = milestone.value.toLocaleString(undefined, { maximumFractionDigits: 1 });
  return (
    <li className="py-3">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-sm font-semibold">{milestone.title}</h3>
        <span className="text-xs text-slate-500">
          {next ? (
            <>
              {value} / {next.target} {milestone.unit} ·{" "}
              <span className={`font-semibold ${theme.text}`}>next +{next.bonus_xp} XP</span>
            </>
          ) : (
            `${value} ${milestone.unit} · all milestones reached`
          )}
        </span>
      </div>
      {next && (
        <div className="mt-2">
          <ProgressBar
            value={milestone.value}
            max={next.target}
            label={`${milestone.title} progress to ${next.target}`}
            fill={theme.fill}
            height="h-2"
          />
        </div>
      )}
      <ul className="mt-2 flex flex-wrap gap-1.5">
        {milestone.tiers.map((tier) => (
          <li
            key={tier.target}
            title={tier.unlocked_on ? `Reached ${longDay(tier.unlocked_on)}` : undefined}
            className={`rounded-full px-2.5 py-1 text-xs font-medium ${
              tier.unlocked ? `${theme.chip} text-white shadow-sm` : "bg-slate-100 text-slate-500"
            }`}
          >
            {tier.target} {milestone.unit}
            <span className="sr-only">{tier.unlocked ? " (reached)" : " (not reached)"}</span>
          </li>
        ))}
      </ul>
    </li>
  );
}

// ── Page ────────────────────────────────────────────────────────────────────

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

  const chartData = {
    labels: data.daily_xp.map((d) => shortDay(d.date)),
    datasets: [
      {
        label: "XP",
        data: data.daily_xp.map((d) => d.xp),
        backgroundColor: data.daily_xp.map((_, i) =>
          i === data.daily_xp.length - 1 ? "#7c3aed" : "#c4b5fd",
        ),
        hoverBackgroundColor: "#8b5cf6",
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
        backgroundColor: "#1e1b4b",
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

  const stats = [
    {
      label: "Total XP",
      value: data.total_xp.toLocaleString(),
      note: `${data.plan_xp.toLocaleString()} from plans · ${data.bonus_xp.toLocaleString()} bonus`,
    },
    { label: "XP last 7 days", value: data.xp_this_week.toLocaleString() },
    { label: "Badges unlocked", value: `${data.badges_unlocked} / ${data.badges_total}` },
    { label: "Plans completed", value: data.plans_completed.toLocaleString() },
  ];

  return (
    <div className="space-y-3">
      <div>
        <div className="text-xs font-semibold text-violet-600">Levels</div>
        <h1 className="text-xl font-bold">Your progress</h1>
      </div>

      <div className="grid gap-3 lg:grid-cols-3">
        <LevelCard data={data} />
        <StreakCard streak={data.streak} />
      </div>

      <section className="grid grid-cols-2 gap-3 lg:grid-cols-4" aria-label="XP stats">
        {stats.map((stat, i) => (
          <div key={stat.label} className="rounded-2xl border border-slate-200 bg-white p-4">
            <div className="flex items-center gap-2 text-xs text-slate-500">
              <span
                aria-hidden="true"
                className={`grid h-6 w-6 place-items-center rounded-lg text-[13px] ${STAT_STYLES[i].chip}`}
              >
                {STAT_STYLES[i].icon}
              </span>
              {stat.label}
            </div>
            <div className="mt-2 text-2xl font-bold">{stat.value}</div>
            {stat.note && <div className="mt-0.5 text-[11px] text-slate-400">{stat.note}</div>}
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
              {data.recent.slice(0, 6).map((event) => (
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
                    <div className="text-sm font-bold text-violet-700">+{event.xp} XP</div>
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
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="font-semibold">Achievements</h2>
          <span className="text-xs text-slate-500">
            {data.badges_unlocked} of {data.badges_total} unlocked
          </span>
        </div>
        {data.recent_unlocks.length > 0 && (
          <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
            <span className="text-slate-500">Latest:</span>
            {data.recent_unlocks.map((unlock) => (
              <span
                key={`${unlock.title}-${unlock.unlocked_on}`}
                className="rounded-full bg-gradient-to-r from-amber-100 to-yellow-50 px-2.5 py-1 font-medium text-amber-900 ring-1 ring-amber-200"
              >
                <span aria-hidden="true">{unlock.icon} </span>
                {unlock.title} · +{unlock.bonus_xp} XP · {longDay(unlock.unlocked_on)}
              </span>
            ))}
          </div>
        )}
        <ul className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {data.achievements.map((badge) => (
            <BadgeCard key={badge.id} badge={badge} />
          ))}
        </ul>
      </section>

      <section className="rounded-2xl border border-slate-200 bg-white p-4">
        <h2 className="font-semibold">Milestones</h2>
        <ul className="divide-y divide-slate-100">
          {data.milestones.map((milestone) => (
            <MilestoneRow key={milestone.id} milestone={milestone} />
          ))}
        </ul>
      </section>

      <section className="rounded-2xl border border-violet-100 bg-violet-50/40 p-4">
        <h2 className="font-semibold">How XP works</h2>
        <ul className="mt-2 space-y-1.5 text-sm text-slate-600">
          <li>
            <span className="font-semibold text-violet-700">+2 XP</span> for recording any
            outcome, even “not started” — honest records help the app learn what works for
            you.
          </li>
          <li>
            <span className="font-semibold text-violet-700">10 XP + 2 × importance</span> for a
            completed plan, plus 1 XP for every 15 planned minutes (up to +8).
          </li>
          <li>Partly done plans earn the same share of that XP as the part you finished.</li>
          <li>
            Unlocking an achievement or milestone adds its{" "}
            <span className="font-semibold text-amber-700">bonus XP</span>.
          </li>
          <li>
            Your <span className="font-semibold text-orange-600">streak</span> grows each day
            you complete at least one plan planned for that day.
          </li>
          <li>Each new level needs 100 XP more than the last one.</li>
        </ul>
      </section>
    </div>
  );
}
