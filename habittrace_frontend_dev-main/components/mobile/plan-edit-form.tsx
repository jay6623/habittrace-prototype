"use client";
import { updateTask, type Task } from "@/lib/api";
import { TASK_CATEGORIES, taskTimeInMinutes, toQuickTaskCreate } from "@/lib/mobile-task";
import QuickAddForm from "./quick-add-form";

export default function PlanEditForm({ task, onDismiss, onSaved }: {
  task: Task; onDismiss: () => void; onSaved: (saved: Task) => void;
}) {
  const minutes = taskTimeInMinutes(task.planned_start_time);
  return <QuickAddForm excludeTaskId={task.id}
    initialDraft={{
      title: task.title, notes: task.notes ?? "", plannedDate: task.planned_date,
      plannedTime: minutes === Number.MAX_SAFE_INTEGER ? "09:00" : `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`,
      durationMinutes: task.planned_duration_min,
      category: TASK_CATEGORIES.includes(task.task_category as typeof TASK_CATEGORIES[number]) ? task.task_category as typeof TASK_CATEGORIES[number] : "Other",
      importance: task.importance,
    }} onDismiss={onDismiss}
    onSubmit={async (draft) => {
      const { title, notes, task_category, planned_start_time, planned_date, planned_duration_min, importance } = toQuickTaskCreate(draft, 1);
      const saved = await updateTask(task.id, { title, notes, task_category, planned_start_time, planned_date, planned_duration_min, importance });
      onSaved(saved);
    }} />;
}
