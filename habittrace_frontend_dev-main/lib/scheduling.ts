import type { Task } from "./api";
import { taskTimeInMinutes } from "./mobile-task";
export function overlappingTasks(tasks: Task[]): Set<string> {
  const conflicts = new Set<string>();
  const pending = tasks.filter((t) => t.task_status === "pending");
  for (let i = 0; i < pending.length; i++)
    for (let j = i + 1; j < pending.length; j++) {
      const a = pending[i],
        b = pending[j];
      const sa = taskTimeInMinutes(a.planned_start_time),
        sb = taskTimeInMinutes(b.planned_start_time);
      if (
        a.planned_date === b.planned_date &&
        sa < sb + b.planned_duration_min &&
        sb < sa + a.planned_duration_min
      ) {
        conflicts.add(a.id);
        conflicts.add(b.id);
      }
    }
  return conflicts;
}
export function findFreeSlots(
  tasks: Task[],
  selected: Task,
  start: string,
  end: string,
  notBefore = 0,
): number[] {
  const slots: number[] = [];
  const stop = taskTimeInMinutes(end);
  for (
    let time =
      Math.ceil(Math.max(taskTimeInMinutes(start), notBefore) / 15) * 15;
    time + selected.planned_duration_min <= stop;
    time += 15
  ) {
    if (
      tasks.every(
        (t) =>
          t.id === selected.id ||
          t.task_status !== "pending" ||
          t.planned_date !== selected.planned_date ||
          time + selected.planned_duration_min + 15 <=
            taskTimeInMinutes(t.planned_start_time) ||
          time >=
            taskTimeInMinutes(t.planned_start_time) +
              t.planned_duration_min +
              15,
      )
    )
      slots.push(time);
  }
  return slots;
}
