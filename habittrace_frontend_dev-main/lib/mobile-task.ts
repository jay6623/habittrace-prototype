import type { TaskCreate } from "@/lib/api";

export const TASK_CATEGORIES = [
  "Study",
  "Work",
  "Chores",
  "Fitness/Health",
  "Errands/Admin",
  "Hobbies/Leisure",
  "Social",
  "Other",
] as const;

export type TaskCategory = (typeof TASK_CATEGORIES)[number];

export const FAILURE_REASONS = [
  { code: "low_readiness", label: "Low energy" },
  { code: "schedule_overload", label: "Too much scheduled" },
  { code: "underestimated_time", label: "Took longer than expected" },
  { code: "interruption", label: "Got interrupted" },
  { code: "unexpected_event", label: "Something unexpected came up" },
  { code: "unclear_plan", label: "Unclear how to start" },
  { code: "task_too_difficult", label: "Harder than expected" },
  { code: "other", label: "Other" },
] as const;

export type FailureReasonCode = (typeof FAILURE_REASONS)[number]["code"];

export interface QuickAddDraft {
  title: string;
  plannedDate: string;
  plannedTime: string;
  durationMinutes: number;
  category: TaskCategory;
  importance: number;
}

export function localDateString(date = new Date()): string {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

export function createQuickAddDefaults(): Pick<
  QuickAddDraft,
  "plannedDate" | "plannedTime"
> {
  const nextSlot = new Date();
  nextSlot.setSeconds(0, 0);
  nextSlot.setMinutes(Math.ceil(nextSlot.getMinutes() / 15) * 15);
  return {
    plannedDate: localDateString(nextSlot),
    plannedTime: `${String(nextSlot.getHours()).padStart(2, "0")}:${String(
      nextSlot.getMinutes(),
    ).padStart(2, "0")}`,
  };
}

export function toStoredTime(time: string): string {
  const [rawHour, minute = "00"] = time.split(":");
  const hour = Number(rawHour);
  const meridiem = hour < 12 ? "AM" : "PM";
  const hour12 = hour % 12 || 12;
  return `${hour12}:${minute} ${meridiem}`;
}

export function taskTimeInMinutes(time: string): number {
  const match = time.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);
  if (!match) return Number.MAX_SAFE_INTEGER;
  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const meridiem = match[3]?.toUpperCase();
  if (minute > 59 || hour > (meridiem ? 12 : 23) || (meridiem && hour < 1)) return Number.MAX_SAFE_INTEGER;
  if (meridiem === "AM" && hour === 12) hour = 0;
  if (meridiem === "PM" && hour !== 12) hour += 12;
  return hour * 60 + minute;
}

export function formatTaskTime(time: string): string {
  const minutes = taskTimeInMinutes(time);
  if (!Number.isFinite(minutes) || minutes === Number.MAX_SAFE_INTEGER) return time;
  const hour = Math.floor(minutes / 60);
  const minute = minutes % 60;
  const period = hour < 12 ? "AM" : "PM";
  return `${hour % 12 || 12}:${String(minute).padStart(2, "0")} ${period}`;
}

export function toQuickTaskCreate(
  draft: QuickAddDraft,
  totalTasksToday: number,
): TaskCreate {
  return {
    title: draft.title.trim(),
    task_category: draft.category,
    planned_start_time: toStoredTime(draft.plannedTime),
    planned_date: draft.plannedDate,
    planned_duration_min: draft.durationMinutes,
    importance: draft.importance,
    energy_level: 3,
    focus_level: 3,
    total_tasks_today: Math.max(1, totalTasksToday),
  };
}
