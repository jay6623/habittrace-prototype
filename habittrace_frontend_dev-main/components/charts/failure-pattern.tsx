"use client";

import {
  Chart as ChartJS,
  ArcElement,
  Tooltip,
  Legend,
} from "chart.js";
import { Doughnut } from "react-chartjs-2";

ChartJS.register(ArcElement, Tooltip, Legend);

const COLORS = ["#0f172a", "#38bdf8", "#fbbf24", "#e2e8f0", "#a78bfa", "#34d399", "#fb7185"];

const options = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      position: "bottom" as const,
      labels: {
        usePointStyle: true,
        pointStyle: "circle",
        padding: 16,
        font: { size: 12 },
      },
    },
    tooltip: {
      backgroundColor: "#0f172a",
      titleFont: { size: 13 },
      bodyFont: { size: 12 },
      padding: 12,
      cornerRadius: 12,
      callbacks: {
        label: function (context: { label: string; parsed: number }) {
          return ` ${context.label}: ${context.parsed}`;
        },
      },
    },
  },
  cutout: "65%",
};

interface Props {
  labels: string[];
  data: number[];
}

export default function FailurePatternChart({ labels, data }: Props) {
  const chartData = {
    labels,
    datasets: [
      {
        data,
        backgroundColor: COLORS.slice(0, labels.length),
        borderWidth: 0,
        hoverOffset: 6,
      },
    ],
  };

  return (
    <div className="h-full flex items-center justify-center">
      <div className="w-full max-w-[280px] h-full">
        <Doughnut options={options} data={chartData} />
      </div>
    </div>
  );
}
