"use client";

import { useSyncExternalStore } from "react";
import {
  Chart as ChartJS, CategoryScale, LinearScale, BarElement, PointElement,
  LineElement, Tooltip, Legend, type ChartOptions,
} from "chart.js";
import { Bar, Line } from "react-chartjs-2";
import {
  chartSeries, coachChartForDisplay, coachChartTick, coachChartTickLimit, isCoachChart, type CoachChartSpec,
} from "@/lib/coach-chart";

ChartJS.register(CategoryScale, LinearScale, BarElement, PointElement, LineElement, Tooltip, Legend);

const themeQuery = "(prefers-color-scheme: dark)";
const subscribeTheme = (notify: () => void) => {
  const media = window.matchMedia(themeQuery);
  media.addEventListener("change", notify);
  return () => media.removeEventListener("change", notify);
};
const darkSnapshot = () => window.matchMedia(themeQuery).matches;
const serverSnapshot = () => false;

export default function CoachChart({ chart: inputChart }: { chart: CoachChartSpec }) {
  const dark = useSyncExternalStore(subscribeTheme, darkSnapshot, serverSnapshot);
  if (!isCoachChart(inputChart)) return null;
  const chart = coachChartForDisplay(inputChart);
  const labelColor = dark ? "#cbd5e1" : "#475569";
  const series = chartSeries(chart);
  const data = {
    labels: series.map(p => p.label),
    datasets: [{
      label: chart.y_axis,
      data: series.map(p => p.value),
      backgroundColor: "#10b981",
      borderColor: "#059669",
      borderWidth: 2,
      pointRadius: 4,
      spanGaps: false,
    }],
  };
  const options: ChartOptions<"bar" | "line"> = {
    responsive: true,
    maintainAspectRatio: false,
    onResize: (instance, size) => {
      const ticks = instance.options.scales?.x?.ticks;
      if (ticks) ticks.maxTicksLimit = coachChartTickLimit(size.width);
    },
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: ctx => {
        const point = series[ctx.dataIndex];
        const counts = point.completed == null ? `n=${point.sample_size}` : `${point.completed}/${point.sample_size} completed`;
        return `${ctx.formattedValue}${chart.units === "percent" ? "%" : " records"} (${counts})`;
      } } },
    },
    scales: {
      x: {
        title: { display: true, text: chart.x_axis, color: labelColor },
        ticks: {
          color: labelColor, maxRotation: 0, minRotation: 0, autoSkip: true,
          autoSkipPadding: 20, maxTicksLimit: 3,
          callback: function(value) { return coachChartTick(this.getLabelForValue(Number(value))); },
        },
        grid: { color: "#94a3b820" },
      },
      y: { beginAtZero: true, ...(chart.units === "percent" ? { max: 100 } : {}), title: { display: true, text: chart.y_axis, color: labelColor }, ticks: { color: labelColor, precision: 0 }, grid: { color: "#94a3b820" } },
    },
  };
  return (
    <figure aria-label={chart.title} className="mt-3 min-w-0 w-full max-w-full rounded-xl border border-slate-200 bg-white p-2 sm:p-3 text-slate-700 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200">
      <figcaption className="text-sm font-semibold">{chart.title}</figcaption>
      <p className="mt-1 text-xs">{chart.period.start} – {chart.period.end} · {chart.sample_size} plotted observations</p>
      <div className="relative mt-3 h-[260px] sm:h-[270px] min-w-0 w-full max-w-full">
        {chart.chart_type === "bar"
          ? <Bar data={data} options={options as ChartOptions<"bar">} role="img" aria-label={chart.title} />
          : <Line data={data} options={options as ChartOptions<"line">} role="img" aria-label={chart.title} />}
      </div>
      <p className="mt-2 text-xs">{chart.note}</p>
      <details className="mt-2 text-xs">
        <summary className="cursor-pointer">View chart data</summary>
        <div className="max-w-full">
          <table className="mt-2 w-full table-fixed text-left [overflow-wrap:anywhere]">
            <caption className="sr-only">{chart.title}</caption>
            <thead><tr><th scope="col">{chart.x_axis}</th><th scope="col">{chart.y_axis}</th><th scope="col">{chart.units === "percent" ? "Completed / total" : "Sample size"}</th></tr></thead>
            <tbody>{chart.data.map(p => <tr key={p.label}><th scope="row">{p.label}</th><td>{p.value}{chart.units === "percent" ? "%" : ""}</td><td>{p.completed == null ? `n=${p.sample_size}` : `${p.completed}/${p.sample_size} completed`}</td></tr>)}</tbody>
          </table>
        </div>
      </details>
    </figure>
  );
}
