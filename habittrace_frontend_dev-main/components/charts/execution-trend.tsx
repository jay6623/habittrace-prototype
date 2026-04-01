"use client";

import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler,
} from "chart.js";
import { Line } from "react-chartjs-2";

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
);

const options = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      position: "top" as const,
      labels: {
        usePointStyle: true,
        pointStyle: "circle",
        padding: 20,
        font: { size: 12 },
      },
    },
    tooltip: {
      backgroundColor: "#0f172a",
      titleFont: { size: 13 },
      bodyFont: { size: 12 },
      padding: 12,
      cornerRadius: 12,
      displayColors: false,
    },
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
  elements: {
    line: { tension: 0.35 },
    point: { radius: 4, hoverRadius: 6 },
  },
};

interface Props {
  labels: string[];
  planned: number[];
  completed: number[];
}

export default function ExecutionTrendChart({ labels, planned, completed }: Props) {
  const data = {
    labels,
    datasets: [
      {
        label: "Planned (min)",
        data: planned,
        borderColor: "#0f172a",
        backgroundColor: "rgba(15, 23, 42, 0.05)",
        fill: true,
        borderWidth: 2,
      },
      {
        label: "Completed (min)",
        data: completed,
        borderColor: "#34d399",
        backgroundColor: "rgba(52, 211, 153, 0.05)",
        fill: true,
        borderWidth: 2,
      },
    ],
  };

  return (
    <div className="h-[240px]">
      <Line options={options} data={data} />
    </div>
  );
}
