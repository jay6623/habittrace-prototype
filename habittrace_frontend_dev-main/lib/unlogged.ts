import type { Task } from "@/lib/api";
import { localDateString, taskTimeInMinutes } from "@/lib/mobile-task";

/** Pending plans scheduled before today still need an outcome. */
export function isUnloggedPastPlan(
  task: Task,
  today = localDateString(),
): boolean {
  return task.task_status === "pending" && task.planned_date < today;
}

export function filterUnloggedPastPlans(
  tasks: Task[],
  today = localDateString(),
): Task[] {
  return tasks
    .filter((task) => isUnloggedPastPlan(task, today))
    .sort((a, b) => {
      if (a.planned_date !== b.planned_date) {
        return a.planned_date < b.planned_date ? 1 : -1;
      }
      return (
        taskTimeInMinutes(b.planned_start_time) -
        taskTimeInMinutes(a.planned_start_time)
      );
    });
}

export function countUnloggedAttention(
  tasks: Task[],
  today = localDateString(),
) {
  return filterUnloggedPastPlans(tasks, today).length;
}

export function formatUnloggedDate(date: string): string {
  return new Date(`${date}T12:00:00`).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}
