import type { Task } from "./api";
import { taskTimeInMinutes, type QuickAddDraft } from "./mobile-task";

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
        rangesOverlap(sa, a.planned_duration_min, sb, b.planned_duration_min)
      ) {
        conflicts.add(a.id);
        conflicts.add(b.id);
      }
    }
  return conflicts;
}

/** Half-open ranges [start, start+duration): touching end-to-start is not an overlap. */
export function rangesOverlap(
  startA: number,
  durationA: number,
  startB: number,
  durationB: number,
): boolean {
  return startA < startB + durationB && startB < startA + durationA;
}

export function findOverlappingTasks(
  draft: Pick<QuickAddDraft, "plannedDate" | "plannedTime" | "durationMinutes">,
  tasks: Task[],
  excludeTaskId?: string,
): Task[] {
  const start = taskTimeInMinutes(draft.plannedTime);
  if (!Number.isFinite(start) || start === Number.MAX_SAFE_INTEGER) return [];
  return tasks.filter((task) => {
    if (excludeTaskId && task.id === excludeTaskId) return false;
    if (task.planned_date !== draft.plannedDate) return false;
    return rangesOverlap(
      start,
      draft.durationMinutes,
      taskTimeInMinutes(task.planned_start_time),
      task.planned_duration_min,
    );
  });
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
