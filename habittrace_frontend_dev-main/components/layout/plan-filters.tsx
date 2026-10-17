"use client";

import { TASK_CATEGORIES } from "@/lib/mobile-task";

export interface PlanFilterState {
  category: string;
  priority: string;
}

export const ALL_PLAN_FILTERS: PlanFilterState = {
  category: "all",
  priority: "all",
};

const PRIORITIES = [
  { value: "1", label: "1 — Low" },
  { value: "2", label: "2" },
  { value: "3", label: "3" },
  { value: "4", label: "4" },
  { value: "5", label: "5 — High" },
];

export function matchesPlanFilters(
  task: { task_category: string; importance: number },
  filters: PlanFilterState,
): boolean {
  if (filters.category !== "all" && task.task_category !== filters.category) return false;
  if (filters.priority !== "all" && String(task.importance) !== filters.priority) return false;
  return true;
}

const selectClass = {
  emerald:
    "min-h-11 rounded-xl border border-emerald-200 bg-white px-3 text-sm font-semibold text-slate-700 outline-none focus:border-emerald-500",
  slate:
    "min-h-11 rounded-xl border border-slate-200 bg-white px-3 text-sm font-medium text-slate-700 outline-none focus:border-slate-400",
};

export default function PlanFilters({
  filters,
  onChange,
  tone = "emerald",
}: {
  filters: PlanFilterState;
  onChange: (next: PlanFilterState) => void;
  tone?: keyof typeof selectClass;
}) {
  return (
    <>
      <select
        aria-label="Filter plans by category"
        className={selectClass[tone]}
        value={filters.category}
        onChange={(event) => onChange({ ...filters, category: event.target.value })}
      >
        <option value="all">All categories</option>
        {TASK_CATEGORIES.map((category) => (
          <option key={category} value={category}>
            {category}
          </option>
        ))}
      </select>
      <select
        aria-label="Filter plans by priority"
        className={selectClass[tone]}
        value={filters.priority}
        onChange={(event) => onChange({ ...filters, priority: event.target.value })}
      >
        <option value="all">All priorities</option>
        {PRIORITIES.map((priority) => (
          <option key={priority.value} value={priority.value}>
            {priority.label}
          </option>
        ))}
      </select>
    </>
  );
}
