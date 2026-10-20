/** Bounded data-only contract shared by streamed and restored coach charts. */
export interface CoachChartSpec {
  chart_type: "bar" | "line";
  title: string;
  x_axis: string;
  y_axis: string;
  units: "percent" | "count";
  period: { start: string; end: string };
  sample_size: number;
  interval_days?: 1 | 7 | null;
  focus?: "hour" | "weekday" | "trend" | "comparison" | "failure" | null;
  note: string;
  data: Array<{ label: string; value: number; sample_size: number; completed?: number | null }>;
}

/** Historical aggregate comparison lines keep their data but render as categorical bars. */
export function coachChartForDisplay(chart: CoachChartSpec): CoachChartSpec {
  if (chart.chart_type === "line" && chart.interval_days == null && chart.data.length === 2 &&
      chart.data.every(p => /^\d{4}-\d{2}-\d{2} – \d{4}-\d{2}-\d{2}$/.test(p.label))) {
    return { ...chart, chart_type: "bar", focus: "comparison", title: "Completion rate by period", x_axis: "Recorded period" };
  }
  return chart;
}

/** Short axis labels only; dataset labels/tooltips and the accessible table retain full dates. */
export function coachChartTick(label: string): string | string[] {
  const format = (day: string) => new Intl.DateTimeFormat("en-US", {
    month: "short", day: "numeric", timeZone: "UTC",
  }).format(new Date(`${day}T00:00:00Z`));
  if (/^\d{4}-\d{2}-\d{2}$/.test(label) && Number.isFinite(Date.parse(label))) return format(label);
  const range = label.match(/^(\d{4}-\d{2}-\d{2}) – (\d{4}-\d{2}-\d{2})$/);
  if (range && range.slice(1).every(day => Number.isFinite(Date.parse(day)))) {
    return [format(range[1]), `– ${format(range[2])}`];
  }
  return label;
}

export function coachChartTickLimit(width: number): number {
  return Math.max(2, Math.min(6, Math.floor(width / 90)));
}

export function isCoachChart(value: unknown): value is CoachChartSpec {
  if (!value || typeof value !== "object") return false;
  const chart = value as CoachChartSpec;
  const text = (s: unknown, max: number) => typeof s === "string" && s.length > 0 && s.length <= max;
  const day = (s: unknown): s is string => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) &&
    Number.isFinite(Date.parse(s)) && new Date(s).toISOString().slice(0, 10) === s;
  return (chart.chart_type === "bar" || chart.chart_type === "line") &&
    (chart.units === "percent" || chart.units === "count") &&
    (chart.interval_days == null || chart.interval_days === 1 || chart.interval_days === 7) &&
    text(chart.title, 200) && text(chart.x_axis, 100) && text(chart.y_axis, 100) &&
    text(chart.note, 500) && !!chart.period && day(chart.period.start) && day(chart.period.end) &&
    chart.period.start <= chart.period.end &&
    Number.isInteger(chart.sample_size) && chart.sample_size >= 5 &&
    Array.isArray(chart.data) && chart.data.length >= 2 && chart.data.length <= 90 &&
    chart.data.every(p => p && text(p.label, 200) && Number.isFinite(p.value) && p.value >= 0 &&
      (chart.units !== "percent" || p.value <= 100) && Number.isInteger(p.sample_size) && p.sample_size > 0 &&
      (p.completed == null || (chart.units === "percent" && Number.isInteger(p.completed) &&
        p.completed >= 0 && p.completed <= p.sample_size &&
        Math.abs(p.value - p.completed / p.sample_size * 100) <= 0.050000001))) &&
    new Set(chart.data.map(p => p.label)).size === chart.data.length &&
    chart.data.reduce((n, p) => n + p.sample_size, 0) === chart.sample_size;
}

/** Missing days stay null so a line never implies unrecorded outcomes. */
export function chartSeries(chart: CoachChartSpec) {
  if (chart.chart_type !== "line") return chart.data;
  const first = chart.data[0]?.label;
  const last = chart.data.at(-1)?.label;
  if (!first || !last || !/^\d{4}-\d{2}-\d{2}$/.test(first) || !/^\d{4}-\d{2}-\d{2}$/.test(last)) return chart.data;
  const points = new Map(chart.data.map(p => [p.label, p]));
  const start = Date.parse(first), end = Date.parse(last);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start || end - start > 90 * 86400000) return chart.data;
  const step = (chart.interval_days ?? 1) * 86400000;
  return Array.from({ length: Math.floor((end - start) / step) + 1 }, (_, i) => {
    const label = new Date(start + i * step).toISOString().slice(0, 10);
    return points.get(label) ?? { label, value: null, sample_size: 0, completed: null };
  });
}
