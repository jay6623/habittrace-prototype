import type { Task } from "./api";
import { localDateString } from "./mobile-task";

/** Reject normalized / repeated DST clock values before sending a private plan. */
export function groupLocalStart(date: string, clock: string): string {
  const start = new Date(`${date}T${clock}:00`);
  if (
    !Number.isFinite(start.getTime()) ||
    localDateString(start) !== date ||
    `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}` !==
      clock
  ) {
    throw new Error("Choose a valid local date and time.");
  }
  if (
    [-1, 1].some((direction) => {
      const other = new Date(start.getTime() + direction * 3600000);
      return (
        localDateString(other) === date &&
        other.getHours() === start.getHours() &&
        other.getMinutes() === start.getMinutes()
      );
    })
  )
    throw new Error("Choose a time outside the repeated daylight-saving hour.");
  return start.toISOString();
}

/** Convert stored legacy plan clocks using the plan's own timezone, including DST. */
export function groupBlockInstant(task: Task): Date {
  const raw = task.planned_start_time.trim();
  const match = /^(\d{1,2}):(\d{2})(?::\d{2})?\s*(AM|PM)?$/i.exec(raw);
  if (!match)
    throw new Error("This block has an unreadable time. Review it in Plans.");
  let hour = Number(match[1]);
  if (match[3]) hour = (hour % 12) + (match[3].toUpperCase() === "PM" ? 12 : 0);
  const target = `${task.planned_date}T${String(hour).padStart(2, "0")}:${match[2]}:00Z`;
  const utc = new Date(target).getTime();
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: task.timezone_name || "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  let candidate = utc;
  for (let i = 0; i < 3; i++) {
    const parts = Object.fromEntries(
      formatter
        .formatToParts(new Date(candidate))
        .map((p) => [p.type, p.value]),
    );
    const represented = Date.parse(
      `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}Z`,
    );
    candidate += utc - represented;
  }
  return new Date(candidate);
}

export function minutesLabel(minutes: number): string {
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const mins = minutes % 60;
  return [
    days ? `${days}d` : "",
    hours ? `${hours}h` : "",
    mins || (!days && !hours) ? `${mins}m` : "",
  ]
    .filter(Boolean)
    .join(" ");
}
