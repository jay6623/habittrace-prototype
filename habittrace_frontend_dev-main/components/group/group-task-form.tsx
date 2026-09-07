"use client";

import { FormEvent, useEffect, useState } from "react";
import type { GroupMember, GroupTaskCreate, GroupTaskPriority } from "@/lib/api";
import { GROUP_TASK_TITLE_MAX_LENGTH, describeApiError, memberName } from "@/lib/group";
import { TASK_CATEGORIES } from "@/lib/mobile-task";

const PRIORITIES: { value: GroupTaskPriority; label: string }[] = [
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
];

interface Draft {
  title: string;
  category: string;
  priority: GroupTaskPriority;
  dueDate: string;
  dueTime: string;
  /** Empty string means unassigned. */
  assignedTo: string;
}

interface GroupTaskFormProps {
  members: GroupMember[];
  currentUserId: string | null;
  onDismiss: () => void;
  onSubmit: (input: GroupTaskCreate) => Promise<void>;
}

const fieldClass =
  "min-h-11 w-full min-w-0 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100";
const labelClass = "mb-1.5 block text-sm font-semibold text-slate-800";

export default function GroupTaskForm({
  members,
  currentUserId,
  onDismiss,
  onSubmit,
}: GroupTaskFormProps) {
  const [draft, setDraft] = useState<Draft>({
    title: "",
    category: "Work",
    priority: "medium",
    dueDate: "",
    dueTime: "",
    assignedTo: "",
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape" && !saving) onDismiss();
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onDismiss, saving]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const title = draft.title.trim();
    if (!title) {
      setError("Enter a task title.");
      return;
    }
    if (title.length > GROUP_TASK_TITLE_MAX_LENGTH) {
      setError(`Keep the title under ${GROUP_TASK_TITLE_MAX_LENGTH} characters.`);
      return;
    }
    if (draft.dueTime && !draft.dueDate) {
      setError("Pick a due date to go with the due time.");
      return;
    }

    setSaving(true);
    setError(null);
    try {
      await onSubmit({
        title,
        category: draft.category,
        priority: draft.priority,
        due_date: draft.dueDate || null,
        due_time: draft.dueTime || null,
        assigned_to: draft.assignedTo || null,
      });
    } catch (caught) {
      setError(describeApiError(caught, "We couldn't save the task. Try again."));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/45 px-4"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !saving) onDismiss();
      }}
    >
      <section
        aria-labelledby="group-task-title"
        aria-modal="true"
        className="max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-3xl bg-white shadow-2xl"
        role="dialog"
      >
        <form onSubmit={handleSubmit}>
          <div className="sticky top-0 z-10 flex items-center justify-between border-b border-slate-100 bg-white/95 px-5 py-4 backdrop-blur">
            <div>
              <p className="text-xs font-semibold text-violet-700">GROUP TASK</p>
              <h2 id="group-task-title" className="text-xl font-bold text-slate-950">
                Add a shared task
              </h2>
            </div>
            <button
              aria-label="Close"
              className="grid h-10 w-10 place-items-center rounded-full bg-slate-100 text-xl text-slate-600 transition hover:bg-slate-200 disabled:opacity-50"
              disabled={saving}
              onClick={onDismiss}
              type="button"
            >
              ×
            </button>
          </div>

          <div className="space-y-4 px-5 py-5">
            <div>
              <label className={labelClass} htmlFor="group-task-name">
                What needs to be done?
              </label>
              <input
                autoFocus
                className={fieldClass}
                id="group-task-name"
                maxLength={GROUP_TASK_TITLE_MAX_LENGTH}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, title: event.target.value }))
                }
                placeholder="e.g. Prepare presentation slides"
                value={draft.title}
              />
            </div>

            <div>
              <label className={labelClass} htmlFor="group-task-assignee">
                Assign to
              </label>
              <select
                className={fieldClass}
                id="group-task-assignee"
                onChange={(event) =>
                  setDraft((current) => ({ ...current, assignedTo: event.target.value }))
                }
                value={draft.assignedTo}
              >
                <option value="">Unassigned</option>
                {members.map((member) => (
                  <option key={member.user_id} value={member.user_id}>
                    {memberName(member, currentUserId)}
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className={labelClass} htmlFor="group-task-category">
                  Category
                </label>
                <select
                  className={fieldClass}
                  id="group-task-category"
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, category: event.target.value }))
                  }
                  value={draft.category}
                >
                  {TASK_CATEGORIES.map((category) => (
                    <option key={category} value={category}>
                      {category}
                    </option>
                  ))}
                </select>
              </div>
              <fieldset>
                <legend className={labelClass}>Priority</legend>
                <div className="grid grid-cols-3 gap-1.5">
                  {PRIORITIES.map((option) => (
                    <button
                      aria-pressed={draft.priority === option.value}
                      className={`min-h-11 rounded-xl text-sm font-semibold transition ${
                        draft.priority === option.value
                          ? "bg-slate-900 text-white"
                          : "border border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
                      }`}
                      key={option.value}
                      onClick={() =>
                        setDraft((current) => ({ ...current, priority: option.value }))
                      }
                      type="button"
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
              </fieldset>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className={labelClass} htmlFor="group-task-date">
                  Due date <span className="font-normal text-slate-400">(optional)</span>
                </label>
                <input
                  className={fieldClass}
                  id="group-task-date"
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, dueDate: event.target.value }))
                  }
                  type="date"
                  value={draft.dueDate}
                />
              </div>
              <div>
                <label className={labelClass} htmlFor="group-task-time">
                  Due time <span className="font-normal text-slate-400">(optional)</span>
                </label>
                <input
                  className={fieldClass}
                  id="group-task-time"
                  onChange={(event) =>
                    setDraft((current) => ({ ...current, dueTime: event.target.value }))
                  }
                  step={300}
                  type="time"
                  value={draft.dueTime}
                />
              </div>
            </div>

            {error && (
              <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700" role="alert">
                {error}
              </p>
            )}
          </div>

          <div className="sticky bottom-0 flex justify-end gap-2 border-t border-slate-100 bg-white px-5 py-4">
            <button
              className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm font-medium transition-colors disabled:opacity-60"
              disabled={saving}
              onClick={onDismiss}
              type="button"
            >
              Cancel
            </button>
            <button
              className="px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60"
              disabled={saving}
              type="submit"
            >
              {saving ? "Saving…" : "Add task"}
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}
