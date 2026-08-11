"use client";

import { useState, useEffect, useCallback, useRef } from "react";
import {
  getTasks, createTask, updateTask, deleteTask, logExecution, createAIOutcome,
  predict, predictAIPlan, getAIPlanPrediction, reviseAIPlan, clearAIPlan,
  createTimeRecommendation, selectTimeCandidate,
  type Task, type TaskCreate, type Prediction, type TaskUpdate, type TimeRecommendation,
} from "@/lib/api";

// ── Constants ─────────────────────────────────────────────────────────────
const CATEGORIES = [
  "Study", "Work", "Chores", "Fitness/Health",
  "Errands/Admin", "Hobbies/Leisure", "Social", "Other",
];
const categoryColors: Record<string, string> = {
  Study:             "bg-sky-100 text-sky-800",
  Work:              "bg-violet-100 text-violet-800",
  Chores:            "bg-amber-100 text-amber-800",
  "Fitness/Health":  "bg-emerald-100 text-emerald-800",
  "Errands/Admin":   "bg-slate-100 text-slate-700",
  "Hobbies/Leisure": "bg-rose-100 text-rose-800",
  Social:            "bg-indigo-100 text-indigo-800",
  Other:             "bg-gray-100 text-gray-700",
};
const FAILURE_REASONS = [
  { value: "low_energy",          label: "Low energy" },
  { value: "low_focus",           label: "Low focus" },
  { value: "start_delay",         label: "Started late" },
  { value: "interruptions",       label: "Interruptions" },
  { value: "time_underestimate",  label: "Underestimated time" },
  { value: "schedule_conflict",   label: "Schedule conflict" },
  { value: "unexpected_event",    label: "Unexpected event" },
  { value: "other",               label: "Other" },
];
const HOURS   = ["1","2","3","4","5","6","7","8","9","10","11","12"];
const MINUTES = ["00","05","10","15","20","25","30","35","40","45","50","55"];

// ── Date helpers (local timezone — no UTC conversion) ──────────────────────
function localDateStr(d = new Date()): string {
  return [
    d.getFullYear(),
    String(d.getMonth() + 1).padStart(2, "0"),
    String(d.getDate()).padStart(2, "0"),
  ].join("-");
}

function offsetDate(base: string, days: number): string {
  const d = new Date(`${base}T12:00:00`);
  d.setDate(d.getDate() + days);
  return localDateStr(d);
}

function formatDateLabel(iso: string): string {
  const today     = localDateStr();
  const tomorrow  = offsetDate(today, 1);
  const yesterday = offsetDate(today, -1);
  if (iso === today)     return "Today";
  if (iso === tomorrow)  return "Tomorrow";
  if (iso === yesterday) return "Yesterday";
  const d = new Date(`${iso}T12:00:00`);
  return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}

// ── Time helpers ──────────────────────────────────────────────────────────
function formatTimeStr(h: string, m: string, mer: "AM" | "PM"): string {
  return `${h}:${m} ${mer}`;
}

function parseTimeStr(s: string): { h: string; m: string; mer: "AM" | "PM" } {
  const match = s.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (match) return { h: match[1], m: match[2], mer: match[3].toUpperCase() as "AM" | "PM" };
  return { h: "9", m: "00", mer: "AM" };
}

function timeToMinutes(timeStr: string): number {
  const { h, m, mer } = parseTimeStr(timeStr);
  let hours = parseInt(h);
  if (mer === "AM" && hours === 12) hours = 0;
  else if (mer === "PM" && hours !== 12) hours += 12;
  return hours * 60 + parseInt(m);
}

function nowTimeParts(): { h: string; m: string; mer: "AM" | "PM" } {
  const now = new Date();
  let h = now.getHours();
  const mer: "AM" | "PM" = h < 12 ? "AM" : "PM";
  if (h === 0) h = 12;
  else if (h > 12) h -= 12;
  const raw = now.getMinutes();
  const m = String(Math.ceil(raw / 5) * 5 % 60).padStart(2, "0");
  return { h: String(h), m, mer };
}

function candidateToTaskTime(candidateStart: string): Pick<TaskUpdate, "planned_start_time" | "planned_date"> {
  const date = new Date(candidateStart);
  if (Number.isNaN(date.getTime())) throw new Error("Invalid recommended time.");
  const hour24 = date.getHours();
  const mer: "AM" | "PM" = hour24 < 12 ? "AM" : "PM";
  const hour12 = hour24 % 12 || 12;
  return {
    planned_start_time: formatTimeStr(
      String(hour12),
      String(date.getMinutes()).padStart(2, "0"),
      mer,
    ),
    planned_date: localDateStr(date),
  };
}

// ── Sub-components ────────────────────────────────────────────────────────
interface LocalTask extends Task {
  actual_start_time: string;
  actual_end_time:   string;
  interruption_count: number;
  stopped_early: boolean;
  failure_reason: string;
  prediction?: Prediction;
}

function RatingDots({ value, onChange, label }: {
  value: number; onChange: (v: number) => void; label: string;
}) {
  return (
    <div>
      <div className="text-xs font-medium text-slate-500 mb-1.5">{label}</div>
      <div className="flex gap-1.5">
        {[1,2,3,4,5].map((n) => (
          <button key={n} onClick={() => onChange(n)}
            className={`h-8 w-8 rounded-lg text-xs font-semibold transition-colors ${
              n <= value ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-400 hover:bg-slate-200"
            }`}
          >{n}</button>
        ))}
      </div>
    </div>
  );
}

function TimePicker({ h, m, mer, onH, onM, onMer, label }: {
  h: string; m: string; mer: "AM" | "PM";
  onH: (v: string) => void; onM: (v: string) => void;
  onMer: (v: "AM" | "PM") => void; label: string;
}) {
  return (
    <div>
      <label className="block text-xs font-medium text-slate-500 mb-1.5">{label}</label>
      <div className="flex items-center gap-1">
        <select value={h} onChange={(e) => onH(e.target.value)}
          className="bg-slate-100 rounded-xl px-2 py-2.5 text-sm outline-none cursor-pointer flex-1 min-w-0">
          {HOURS.map((v) => <option key={v} value={v}>{v}</option>)}
        </select>
        <span className="text-slate-400 font-semibold text-sm">:</span>
        <select value={m} onChange={(e) => onM(e.target.value)}
          className="bg-slate-100 rounded-xl px-2 py-2.5 text-sm outline-none cursor-pointer flex-1 min-w-0">
          {MINUTES.map((v) => <option key={v} value={v}>{v}</option>)}
        </select>
        <div className="flex rounded-xl overflow-hidden border border-slate-200 shrink-0">
          {(["AM","PM"] as const).map((t) => (
            <button key={t} onClick={() => onMer(t)}
              className={`px-2.5 py-2.5 text-xs font-semibold transition-colors ${
                mer === t ? "bg-slate-900 text-white" : "bg-white text-slate-500 hover:bg-slate-50"
              }`}
            >{t}</button>
          ))}
        </div>
      </div>
    </div>
  );
}

function PredictionBadge({ prediction, loading }: { prediction?: Prediction; loading?: boolean }) {
  if (loading && !prediction) return (
    <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-400 animate-pulse">
      predicting…
    </span>
  );
  if (!prediction) return null;
  const pct = Math.round(prediction.success_probability * 100);
  const color = pct >= 70 ? "bg-emerald-100 text-emerald-800"
              : pct >= 50 ? "bg-amber-100 text-amber-800"
              :             "bg-rose-100 text-rose-800";
  return (
    <span
      title={loading ? "Updating success probability" : "Predicted success probability"}
      className={`text-xs px-2 py-0.5 rounded-full font-medium ${color} ${loading ? "opacity-70 animate-pulse" : ""}`}
    >
      {pct}% success{loading ? " · updating" : ""}
    </span>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────
export default function HabitTrackingPage() {
  const [viewDate, setViewDate]   = useState(localDateStr);
  const [tasks, setTasks]         = useState<LocalTask[]>([]);
  const [loading, setLoading]     = useState(true);
  const [apiError, setApiError]   = useState<string | null>(null);
  const [showAddForm, setShowAddForm]     = useState(false);
  const [completingTaskId, setCompletingTaskId] = useState<string | null>(null);
  const [editingTaskId, setEditingTaskId]       = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  // Track which task IDs have predictions loading
  const [predLoading, setPredLoading] = useState<Set<string>>(new Set());
  const [timeRecommendations, setTimeRecommendations] = useState<Record<string, TimeRecommendation>>({});
  const [timeRecommendationLoading, setTimeRecommendationLoading] = useState<Set<string>>(new Set());

  // ── Add form ──────────────────────────────────────────────────────────
  const [newTitle,      setNewTitle]      = useState("");
  const [newCategory,   setNewCategory]   = useState("Study");
  const [newDate,       setNewDate]       = useState(localDateStr);
  const [newHour,       setNewHour]       = useState(() => nowTimeParts().h);
  const [newMin,        setNewMin]        = useState(() => nowTimeParts().m);
  const [newMer,        setNewMer]        = useState<"AM"|"PM">(() => nowTimeParts().mer);
  const [newDuration,   setNewDuration]   = useState("60");
  const [newImportance, setNewImportance] = useState(3);
  const [newEnergy,     setNewEnergy]     = useState(3);
  const [newFocus,      setNewFocus]      = useState(3);

  // ── Edit form ─────────────────────────────────────────────────────────
  const [editTitle,      setEditTitle]      = useState("");
  const [editCategory,   setEditCategory]   = useState("Study");
  const [editDate,       setEditDate]       = useState(localDateStr);
  const [editHour,       setEditHour]       = useState("9");
  const [editMin,        setEditMin]        = useState("00");
  const [editMer,        setEditMer]        = useState<"AM"|"PM">("AM");
  const [editDuration,   setEditDuration]   = useState("60");
  const [editImportance, setEditImportance] = useState(3);
  const [editEnergy,     setEditEnergy]     = useState(3);
  const [editFocus,      setEditFocus]      = useState(3);

  // ── Complete form ─────────────────────────────────────────────────────
  const [actStartH,   setActStartH]   = useState("9");
  const [actStartM,   setActStartM]   = useState("00");
  const [actStartMer, setActStartMer] = useState<"AM"|"PM">("AM");
  const [actEndH,     setActEndH]     = useState("10");
  const [actEndM,     setActEndM]     = useState("00");
  const [actEndMer,   setActEndMer]   = useState<"AM"|"PM">("AM");
  const [interruptions, setInterruptions] = useState("0");
  const [stoppedEarly,  setStoppedEarly]  = useState(false);
  const [taskResult,    setTaskResult]    = useState<"success"|"failed">("success");
  const [failureReason, setFailureReason] = useState("");

  // ── Fire predictions for a list of tasks ─────────────────────────────
  // Use a ref to avoid stale closure issues with the latest total count
  const totalRef = useRef(0);

  function firePredictions(pendingTasks: LocalTask[], total: number) {
    if (pendingTasks.length === 0) return;
    totalRef.current = total;

    setPredLoading((prev) => {
      const next = new Set(prev);
      pendingTasks.forEach((t) => next.add(t.id));
      return next;
    });

    pendingTasks.forEach((t) => {
      const predictionRequest = t.ai_plan_input_id
        ? getAIPlanPrediction(t.ai_plan_input_id).then(
            (existing) => existing ?? predictAIPlan(t.ai_plan_input_id as string)
          )
        : predict({
            task_category: t.task_category,
            planned_start_time: t.planned_start_time,
            planned_date: t.planned_date,
            planned_duration_min: t.planned_duration_min,
            importance: t.importance,
            energy_level: t.energy_level,
            focus_level: t.focus_level,
            total_tasks_today: total,
          });
      predictionRequest
        .then((pred) => {
          setTasks((prev) => prev.map((x) =>
            x.id === t.id ? { ...x, prediction: pred } : x
          ));
        })
        .catch(() => {})
        .finally(() => {
          setPredLoading((prev) => {
            const next = new Set(prev);
            next.delete(t.id);
            return next;
          });
        });
    });
  }

  async function requestTimeRecommendation(task: LocalTask) {
    if (!task.ai_plan_input_id) {
      alert("Time recommendations require a signed-in AI plan.");
      return;
    }
    setTimeRecommendationLoading((prev) => new Set(prev).add(task.id));
    try {
      const recommendation = await createTimeRecommendation(
        task.ai_plan_input_id,
        task.planned_date,
      );
      setTimeRecommendations((prev) => ({ ...prev, [task.id]: recommendation }));
    } catch (error) {
      console.warn("Time recommendation failed:", error);
      alert("Could not generate time recommendations for this task.");
    } finally {
      setTimeRecommendationLoading((prev) => {
        const next = new Set(prev);
        next.delete(task.id);
        return next;
      });
    }
  }

  async function chooseTimeCandidate(taskId: string, recommendation: TimeRecommendation, candidateId: string) {
    const task = tasks.find((item) => item.id === taskId);
    const candidate = recommendation.candidates.find((item) => item.id === candidateId);
    if (!task || !candidate) return;

    // Update the card immediately so the user gets feedback even while the
    // persistence request is in flight. The server response remains the source
    // of truth once it arrives.
    setTimeRecommendations((prev) => ({
      ...prev,
      [taskId]: { ...recommendation, selected_candidate_id: candidateId, status: "accepted" },
    }));
    try {
      const updated = await selectTimeCandidate(recommendation.id, candidateId);
      const savedRecommendation = {
        ...updated,
        // Keep the visual selection even if an older backend response omits
        // the selected id from its representation.
        selected_candidate_id: updated.selected_candidate_id ?? candidateId,
      };
      setTimeRecommendations((prev) => ({
        ...prev,
        [taskId]: savedRecommendation,
      }));

      // Keep the legacy service task and the visible task list in sync with the
      // accepted AI recommendation.
      try {
        const taskUpdate = candidateToTaskTime(candidate.candidate_start);
        const updatedTask = await updateTask(taskId, taskUpdate);
        const revisedTask: TaskCreate = {
          title: updatedTask.title,
          task_category: updatedTask.task_category,
          planned_start_time: updatedTask.planned_start_time,
          planned_date: updatedTask.planned_date,
          planned_duration_min: updatedTask.planned_duration_min,
          importance: updatedTask.importance,
          energy_level: updatedTask.energy_level,
          focus_level: updatedTask.focus_level,
          total_tasks_today: tasks.length,
        };

        // A changed start time is a new immutable AI plan revision. This makes
        // the task-list prediction reflect the accepted recommendation rather
        // than leaving the old success probability attached to the task.
        let revisedPlanId = task.ai_plan_input_id;
        if (task.ai_plan_input_id) {
          try {
            revisedPlanId = await reviseAIPlan(taskId, task.ai_plan_input_id, revisedTask);
          } catch (error) {
            clearAIPlan(taskId);
            revisedPlanId = undefined;
            console.warn("AI plan revision after time selection failed:", error);
          }
        }

        const patchedTask: LocalTask = {
          ...task,
          ...updatedTask,
          ai_plan_input_id: revisedPlanId,
          // Keep the previous value visible until the revised prediction
          // arrives, instead of making the task row appear empty.
          prediction: task.prediction,
        };
        setTasks((prev) => prev.map((item) => (
          item.id === taskId ? patchedTask : item
        )));
        firePredictions([patchedTask], tasks.length);
      } catch (error) {
        console.warn("Task update after time selection failed:", error);
        const detail = error instanceof Error ? error.message : "Unknown API error";
        alert(`추천 시간은 저장되었지만 작업 목록 업데이트에 실패했습니다.\n${detail}`);
      }
    } catch (error) {
      setTimeRecommendations((prev) => ({ ...prev, [taskId]: recommendation }));
      console.warn("Time candidate selection failed:", error);
      const detail = error instanceof Error ? error.message : "Unknown API error";
      alert(`Could not save the selected time.\n${detail}`);
    }
  }

  function previewTimeCandidate(
    taskId: string,
    recommendation: TimeRecommendation,
    candidateId: string,
  ) {
    setTimeRecommendations((prev) => ({
      ...prev,
      [taskId]: {
        ...recommendation,
        selected_candidate_id: candidateId,
        status: recommendation.selected_candidate_id === candidateId
          ? recommendation.status
          : "generated",
      },
    }));
  }

  // ── Load tasks ────────────────────────────────────────────────────────
  const loadTasks = useCallback((date: string) => {
    setLoading(true);
    getTasks(date)
      .then((serverTasks) => {
        const local: LocalTask[] = serverTasks.map((t) => ({
          ...t,
          actual_start_time: "", actual_end_time: "",
          interruption_count: 0, stopped_early: false, failure_reason: "",
        }));
        setTasks(local);
        setApiError(null);
        // Always re-run predictions after loading
        const pending = local.filter((t) => t.task_status === "pending");
        firePredictions(pending, local.length);
      })
      .catch((err) => {
        console.warn("Could not load tasks:", err.message);
        setApiError("Backend not reachable — showing local data only.");
      })
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => { loadTasks(viewDate); }, [viewDate, loadTasks]);

  // Sync newDate with viewDate when form opens
  useEffect(() => {
    if (showAddForm) setNewDate(viewDate);
  }, [showAddForm, viewDate]);

  // ── Stats ─────────────────────────────────────────────────────────────
  const totalTasks     = tasks.length;
  const successTasks   = tasks.filter((t) => t.task_status === "success").length;
  const failedTasks    = tasks.filter((t) => t.task_status === "failed").length;
  const pendingTasks   = tasks.filter((t) => t.task_status === "pending").length;
  const completionRate = totalTasks > 0 ? Math.round((successTasks / totalTasks) * 100) : 0;
  const totalPlanned   = tasks.reduce((s, t) => s + t.planned_duration_min, 0);
  const avgImportance  = tasks.length > 0
    ? (tasks.reduce((s, t) => s + t.importance, 0) / tasks.length).toFixed(1) : "0";

  // ── Add task ──────────────────────────────────────────────────────────
  async function handleAddTask() {
    if (!newTitle.trim()) { alert("Please fill in the task name."); return; }
    const timeStr = formatTimeStr(newHour, newMin, newMer);
    setSaving(true);
    const totalToday = tasks.length + 1;
    try {
      let serverTask: Task | null = null;
      try {
        serverTask = await createTask({
          title: newTitle.trim(), task_category: newCategory,
          planned_start_time: timeStr, planned_date: newDate,
          planned_duration_min: parseInt(newDuration),
          importance: newImportance, energy_level: newEnergy,
          focus_level: newFocus, total_tasks_today: totalToday,
        });
      } catch (e) { console.warn("createTask failed:", e); }

      const localTask: LocalTask = {
        id: serverTask?.id ?? Date.now().toString(),
        user_id: serverTask?.user_id ?? "demo-user",
        title: newTitle.trim(), task_category: newCategory,
        planned_start_time: timeStr, planned_date: newDate,
        planned_duration_min: parseInt(newDuration),
        importance: newImportance, energy_level: newEnergy,
        focus_level: newFocus, total_tasks_today: totalToday,
        task_status: "pending", created_at: new Date().toISOString(),
        ai_plan_input_id: serverTask?.ai_plan_input_id,
        actual_start_time: "", actual_end_time: "",
        interruption_count: 0, stopped_early: false, failure_reason: "",
      };

      if (newDate === viewDate) {
        setTasks((prev) => [...prev, localTask]);
        // Fire prediction for the new task immediately
        firePredictions([localTask], totalToday);
      } else {
        setViewDate(newDate); // triggers reload for that date
      }

      const t = nowTimeParts();
      setNewTitle(""); setNewHour(t.h); setNewMin(t.m); setNewMer(t.mer);
      setNewImportance(3); setNewEnergy(3); setNewFocus(3);
      setShowAddForm(false);
    } finally { setSaving(false); }
  }

  // ── Open edit form ────────────────────────────────────────────────────
  function openEditForm(task: LocalTask) {
    const tp = parseTimeStr(task.planned_start_time);
    setEditTitle(task.title);
    setEditCategory(task.task_category);
    setEditDate(task.planned_date);
    setEditHour(tp.h); setEditMin(tp.m); setEditMer(tp.mer);
    setEditDuration(String(task.planned_duration_min));
    setEditImportance(task.importance);
    setEditEnergy(task.energy_level);
    setEditFocus(task.focus_level);
    setEditingTaskId(task.id);
    setCompletingTaskId(null);
    setShowAddForm(false);
  }

  // ── Save edit ─────────────────────────────────────────────────────────
  async function handleSaveEdit() {
    if (!editingTaskId || !editTitle.trim()) return;
    const timeStr = formatTimeStr(editHour, editMin, editMer);
    const update: TaskUpdate = {
      title: editTitle.trim(), task_category: editCategory,
      planned_start_time: timeStr, planned_date: editDate,
      planned_duration_min: parseInt(editDuration),
      importance: editImportance, energy_level: editEnergy, focus_level: editFocus,
    };
    setSaving(true);
    try {
      const currentTask = tasks.find((t) => t.id === editingTaskId);
      if (!currentTask) return;

      const revisedTask: TaskCreate = {
        title: update.title ?? currentTask.title,
        task_category: update.task_category ?? currentTask.task_category,
        planned_start_time: update.planned_start_time ?? currentTask.planned_start_time,
        planned_date: update.planned_date ?? currentTask.planned_date,
        planned_duration_min: update.planned_duration_min ?? currentTask.planned_duration_min,
        importance: update.importance ?? currentTask.importance,
        energy_level: update.energy_level ?? currentTask.energy_level,
        focus_level: update.focus_level ?? currentTask.focus_level,
        total_tasks_today: tasks.length,
      };

      // Optimistic update
      setTasks((prev) => prev.map((t) =>
        t.id !== editingTaskId ? t
        : { ...t, ...update, prediction: undefined }
      ));

      // Persist the legacy task and create an immutable AI revision separately.
      let serviceUpdateSucceeded = true;
      await updateTask(editingTaskId, update).catch((e) => {
        serviceUpdateSucceeded = false;
        console.warn("updateTask failed, local only:", e);
      });

      let revisedPlanId = currentTask.ai_plan_input_id;
      if (currentTask.ai_plan_input_id && serviceUpdateSucceeded) {
        try {
          revisedPlanId = await reviseAIPlan(
            editingTaskId,
            currentTask.ai_plan_input_id,
            revisedTask,
          );
        } catch (error) {
          clearAIPlan(editingTaskId);
          revisedPlanId = undefined;
          console.warn("AI V2 plan revision was not created:", error);
        }
      } else if (!serviceUpdateSucceeded) {
        clearAIPlan(editingTaskId);
        revisedPlanId = undefined;
      }

      const patched: LocalTask = {
        ...currentTask,
        ...update,
        ai_plan_input_id: revisedPlanId,
        prediction: undefined,
      };
      setTasks((prev) => prev.map((t) =>
        t.id === editingTaskId ? patched : t
      ));
      firePredictions([patched], tasks.length);
      setEditingTaskId(null);
    } finally { setSaving(false); }
  }

  // ── Open complete form ────────────────────────────────────────────────
  function openCompleteForm(task: LocalTask) {
    setCompletingTaskId(task.id);
    const t = nowTimeParts();
    setActStartH(t.h); setActStartM(t.m); setActStartMer(t.mer);
    const now = new Date();
    const end = new Date(now.getTime() + task.planned_duration_min * 60000);
    let eh = end.getHours();
    const eMer: "AM"|"PM" = eh < 12 ? "AM" : "PM";
    if (eh === 0) eh = 12; else if (eh > 12) eh -= 12;
    const em = String(Math.ceil(end.getMinutes() / 5) * 5 % 60).padStart(2, "0");
    setActEndH(String(eh)); setActEndM(em); setActEndMer(eMer);
    setInterruptions("0"); setStoppedEarly(false);
    setTaskResult("success"); setFailureReason("");
    setEditingTaskId(null);
    setShowAddForm(false);
  }

  // ── Submit results ────────────────────────────────────────────────────
  async function handleSubmitResults() {
    if (taskResult === "failed" && !failureReason) {
      alert("Please select a reason for failure."); return;
    }
    const startStr = formatTimeStr(actStartH, actStartM, actStartMer);
    const endStr   = formatTimeStr(actEndH, actEndM, actEndMer);
    setSaving(true);
    try {
      if (completingTaskId) {
        const completedTask = tasks.find((task) => task.id === completingTaskId);
        await logExecution({
          task_id: completingTaskId,
          actual_start_time: startStr, actual_end_time: endStr,
          interruption_count: parseInt(interruptions),
          stopped_early: stoppedEarly, task_status: taskResult,
          failure_reason: taskResult === "failed" ? failureReason : undefined,
        }).catch((e) => console.warn("logExecution failed:", e));
        if (completedTask?.ai_plan_input_id) {
          await createAIOutcome({
            task: completedTask,
            taskResult,
            actualStartTime: startStr,
            actualEndTime: endStr,
            interruptionCount: parseInt(interruptions),
            stoppedEarly,
            failureReason: taskResult === "failed" ? failureReason : undefined,
          }).catch((e) => console.warn("AI V2 outcome was not created:", e));
        }
      }
      setTasks((prev) => prev.map((t) => {
        if (t.id !== completingTaskId) return t;
        return {
          ...t, actual_start_time: startStr, actual_end_time: endStr,
          interruption_count: parseInt(interruptions),
          stopped_early: stoppedEarly, task_status: taskResult,
          failure_reason: taskResult === "failed" ? failureReason : "",
        };
      }));
      setCompletingTaskId(null);
    } finally { setSaving(false); }
  }

  function resetTask(id: string) {
    setTasks((prev) => prev.map((t) =>
      t.id !== id ? t : {
        ...t, actual_start_time: "", actual_end_time: "",
        interruption_count: 0, stopped_early: false,
        task_status: "pending" as const, failure_reason: "",
      }
    ));
    // Re-fire prediction after reset
    const task = tasks.find((t) => t.id === id);
    if (task) firePredictions([{ ...task, task_status: "pending" }], tasks.length);
  }

  async function handleDeleteTask(id: string) {
    setTasks((prev) => prev.filter((t) => t.id !== id));
    if (completingTaskId === id) setCompletingTaskId(null);
    if (editingTaskId === id) setEditingTaskId(null);
    deleteTask(id).catch(() => {});
  }

  // ── Render ────────────────────────────────────────────────────────────
  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <div className="text-sm text-slate-500">Habit Tracking</div>
          <h1 className="text-2xl font-bold">Tasks</h1>
        </div>
        <button
          onClick={() => { setShowAddForm(!showAddForm); setCompletingTaskId(null); setEditingTaskId(null); }}
          className="px-4 py-2 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors"
        >{showAddForm ? "Cancel" : "+ Add task"}</button>
      </div>

      {/* Date navigation */}
      <div className="flex items-center gap-2">
        <button onClick={() => setViewDate(offsetDate(viewDate, -1))}
          className="h-9 w-9 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 grid place-items-center">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold min-w-[90px] text-center">{formatDateLabel(viewDate)}</span>
          <input type="date" value={viewDate} onChange={(e) => setViewDate(e.target.value)}
            className="bg-slate-100 rounded-xl px-3 py-1.5 text-xs outline-none cursor-pointer border border-transparent focus:bg-white focus:border-slate-200"/>
        </div>
        <button onClick={() => setViewDate(offsetDate(viewDate, 1))}
          className="h-9 w-9 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 grid place-items-center">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <path d="M9 18l6-6-6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        {viewDate !== localDateStr() && (
          <button onClick={() => setViewDate(localDateStr())}
            className="text-xs px-3 py-1.5 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-600 transition-colors">
            Today
          </button>
        )}
      </div>

      {apiError && (
        <div className="px-4 py-3 rounded-xl bg-amber-50 border border-amber-100 text-sm text-amber-700">{apiError}</div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-5 gap-4">
        {[
          { label: "Success rate", main: `${completionRate}%`, sub: null, bar: completionRate },
          { label: "Tasks",        main: `${successTasks} / ${totalTasks}`, sub: `${pendingTasks} pending · ${failedTasks} failed`, bar: null },
          { label: "Planned time", main: `${totalPlanned}`,    sub: "minutes", bar: null },
          { label: "Avg importance", main: avgImportance,      sub: "out of 5", bar: null },
          { label: "Total tasks",    main: `${totalTasks}`,    sub: "feeds into ML", bar: null },
        ].map(({ label, main, sub, bar }) => (
          <div key={label} className="bg-white rounded-2xl border border-slate-200 p-4">
            <div className="text-xs text-slate-500">{label}</div>
            <div className="text-2xl font-bold mt-1">{main}</div>
            {sub && <div className="text-xs text-slate-500 mt-1">{sub}</div>}
            {bar !== null && (
              <div className="mt-2 h-2 rounded-full bg-slate-100 overflow-hidden">
                <div className="h-full bg-emerald-400 rounded-full" style={{ width: `${bar}%` }} />
              </div>
            )}
          </div>
        ))}
      </div>

      {/* ── Add form ──────────────────────────────────────────────────── */}
      {showAddForm && (
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="flex items-center gap-2 mb-4">
            <div className="h-6 w-6 rounded-full bg-slate-900 text-white grid place-items-center text-xs font-bold">1</div>
            <div className="font-semibold text-sm">Plan your task</div>
          </div>
          <div className="grid sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Task name</label>
              <input className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
                placeholder="Read chapter 4" value={newTitle} onChange={(e) => setNewTitle(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleAddTask()} />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Category</label>
              <select className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer"
                value={newCategory} onChange={(e) => setNewCategory(e.target.value)}>
                {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
          </div>
          <div className="grid sm:grid-cols-3 gap-4 mt-4">
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Date</label>
              <input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)}
                className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer border border-transparent focus:bg-white focus:border-slate-200"/>
            </div>
            <TimePicker label="Planned start time" h={newHour} m={newMin} mer={newMer}
              onH={setNewHour} onM={setNewMin} onMer={setNewMer} />
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Duration</label>
              <select className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer"
                value={newDuration} onChange={(e) => setNewDuration(e.target.value)}>
                {[15,30,45,60,90,120].map((m) => <option key={m} value={m}>{m} min</option>)}
              </select>
            </div>
          </div>
          <div className="mt-4 grid sm:grid-cols-3 gap-4">
            <RatingDots label="Importance (1–5)"   value={newImportance} onChange={setNewImportance} />
            <RatingDots label="Energy level (1–5)" value={newEnergy}     onChange={setNewEnergy} />
            <RatingDots label="Focus level (1–5)"  value={newFocus}      onChange={setNewFocus} />
          </div>
          <div className="mt-4 px-3 py-2 rounded-xl bg-slate-50 text-xs text-slate-500">
            Saving as{" "}
            <span className="font-semibold text-slate-700">
              {formatDateLabel(newDate)} at {formatTimeStr(newHour, newMin, newMer)}
            </span>
            {" "}· {newDuration} min
          </div>
          <div className="mt-4 flex justify-end">
            <button onClick={handleAddTask} disabled={saving}
              className="px-4 py-2.5 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors disabled:opacity-60">
              {saving ? "Saving…" : "Add task to plan"}
            </button>
          </div>
        </div>
      )}

      {/* ── Complete form ──────────────────────────────────────────────── */}
      {completingTaskId && (
        <div className="bg-white rounded-2xl border-2 border-emerald-200 p-5">
          <div className="flex items-center gap-2 mb-4">
            <div className="h-6 w-6 rounded-full bg-emerald-500 text-white grid place-items-center text-xs font-bold">2</div>
            <div className="font-semibold text-sm">
              Log results: {tasks.find((t) => t.id === completingTaskId)?.title}
            </div>
          </div>
          <div className="grid sm:grid-cols-2 gap-4">
            <TimePicker label="Actual start time" h={actStartH} m={actStartM} mer={actStartMer}
              onH={setActStartH} onM={setActStartM} onMer={setActStartMer} />
            <TimePicker label="Actual end time"   h={actEndH}   m={actEndM}   mer={actEndMer}
              onH={setActEndH}   onM={setActEndM}   onMer={setActEndMer} />
          </div>
          <div className="grid sm:grid-cols-2 gap-4 mt-4">
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Interruptions</label>
              <select className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer"
                value={interruptions} onChange={(e) => setInterruptions(e.target.value)}>
                {[0,1,2,3,4,5].map((n) => <option key={n} value={n}>{n} {n===1?"time":"times"}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Stopped early?</label>
              <div className="flex gap-2">
                {([false,true] as const).map((v) => (
                  <button key={String(v)} onClick={() => setStoppedEarly(v)}
                    className={`flex-1 py-2.5 rounded-xl text-sm font-medium transition-colors ${
                      stoppedEarly === v ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500"
                    }`}>{v ? "Yes" : "No"}</button>
                ))}
              </div>
            </div>
          </div>
          <div className="mt-4 grid sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-slate-500 mb-1.5">Task result</label>
              <div className="flex gap-2">
                <button onClick={() => setTaskResult("success")}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                    taskResult==="success" ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-500 hover:bg-slate-200"
                  }`}>Success</button>
                <button onClick={() => setTaskResult("failed")}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                    taskResult==="failed" ? "bg-rose-500 text-white" : "bg-slate-100 text-slate-500 hover:bg-slate-200"
                  }`}>Failed</button>
              </div>
            </div>
            {taskResult === "failed" && (
              <div>
                <label className="block text-xs font-medium text-slate-500 mb-1.5">Reason for failure</label>
                <select className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer"
                  value={failureReason} onChange={(e) => setFailureReason(e.target.value)}>
                  <option value="">Select a reason…</option>
                  {FAILURE_REASONS.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}
                </select>
              </div>
            )}
          </div>
          <div className="mt-4 flex justify-end gap-3">
            <button onClick={() => setCompletingTaskId(null)}
              className="px-4 py-2.5 rounded-xl bg-slate-100 text-sm font-medium hover:bg-slate-200 transition-colors">Cancel</button>
            <button onClick={handleSubmitResults} disabled={saving}
              className="px-4 py-2.5 rounded-xl bg-emerald-500 text-white text-sm font-semibold hover:bg-emerald-600 transition-colors disabled:opacity-60">
              {saving ? "Saving…" : "Save results"}
            </button>
          </div>
        </div>
      )}

      {/* ── Task list ─────────────────────────────────────────────────── */}
      <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
        <div className="p-5 border-b border-slate-200">
          <div className="font-semibold">Task list</div>
          <div className="text-sm text-slate-500">
            {formatDateLabel(viewDate)} — click &quot;Log results&quot; after finishing a task
          </div>
        </div>

        {loading ? (
          <div className="px-5 py-12 text-center text-sm text-slate-400 animate-pulse">Loading tasks…</div>
        ) : (
          <div className="divide-y divide-slate-100">
            {[...tasks].sort((a, b) => timeToMinutes(a.planned_start_time) - timeToMinutes(b.planned_start_time)).map((task) => (
              <div key={task.id}>
                {/* Task row */}
                <div className={`px-5 py-4 transition-colors ${
                  task.task_status === "success" ? "bg-emerald-50/40" :
                  task.task_status === "failed"  ? "bg-rose-50/40" : ""
                }`}>
                  <div className="flex items-start gap-4">
                    <div className={`mt-1 h-3 w-3 rounded-full shrink-0 ${
                      task.task_status === "success" ? "bg-emerald-400" :
                      task.task_status === "failed"  ? "bg-rose-400" : "bg-slate-300"
                    }`} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className={`text-sm font-medium ${task.task_status !== "pending" ? "text-slate-400" : "text-slate-900"}`}>
                          {task.title}
                        </span>
                        <span className={`text-xs px-2 py-0.5 rounded-full ${categoryColors[task.task_category] ?? "bg-slate-100 text-slate-600"}`}>
                          {task.task_category}
                        </span>
                        {task.task_status === "success" && <span className="text-xs px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700 font-medium">Done</span>}
                        {task.task_status === "failed"  && <span className="text-xs px-2 py-0.5 rounded-full bg-rose-100 text-rose-700 font-medium">Failed</span>}
                        {/* Prediction badge — always visible for pending */}
                        {task.task_status === "pending" && (
                          <PredictionBadge
                            prediction={task.prediction}
                            loading={predLoading.has(task.id)}
                          />
                        )}
                      </div>
                      <div className="text-xs text-slate-500 mt-1 flex flex-wrap gap-x-3 gap-y-0.5">
                        <span>{task.planned_start_time} · {task.planned_duration_min} min</span>
                        <span>Importance: {task.importance}/5</span>
                        <span>Energy: {task.energy_level}/5</span>
                        <span>Focus: {task.focus_level}/5</span>
                      </div>
                      {task.task_status === "pending" && task.prediction?.predicted_failure_reason && (
                        <div className="text-xs text-amber-600 mt-0.5">
                          Watch out: {task.prediction.predicted_failure_reason.replace(/_/g, " ")}
                        </div>
                      )}
                      {task.task_status === "pending" && task.prediction?.recommended_actions?.length ? (
                        <div className="mt-2 rounded-xl bg-slate-50 border border-slate-100 px-3 py-2">
                          <div className="text-[11px] font-semibold text-slate-600">Try this</div>
                          <div className="mt-1 flex flex-wrap gap-1.5">
                            {task.prediction.recommended_actions.slice(0, 2).map((action) => (
                              <span key={action.code} title={action.detail}
                                className="text-[11px] px-2 py-1 rounded-lg bg-white border border-slate-200 text-slate-600">
                                {action.title}
                              </span>
                            ))}
                          </div>
                        </div>
                      ) : null}
                      {task.task_status !== "pending" && (
                        <div className="text-xs mt-1.5 flex flex-wrap gap-x-3 gap-y-0.5">
                          <span className="text-slate-500">Actual: {task.actual_start_time} – {task.actual_end_time}</span>
                          <span className="text-slate-500">{task.interruption_count} interruption{task.interruption_count !== 1 ? "s" : ""}</span>
                          {task.stopped_early && <span className="text-amber-600">Stopped early</span>}
                          {task.failure_reason && (
                            <span className="text-rose-600">
                              {FAILURE_REASONS.find((r) => r.value === task.failure_reason)?.label ?? task.failure_reason}
                            </span>
                          )}
                        </div>
                      )}
                    </div>

                    {/* Action buttons */}
                    <div className="flex items-center gap-1.5 shrink-0">
                      {task.task_status === "pending" && (
                        <button onClick={() => { openCompleteForm(task); }}
                          className="text-xs px-3 py-1.5 rounded-lg bg-emerald-100 text-emerald-700 hover:bg-emerald-200 font-medium transition-colors">
                          Log results
                        </button>
                      )}
                      {task.task_status === "pending" && task.ai_plan_input_id && (
                        <button
                          onClick={() => requestTimeRecommendation(task)}
                          disabled={timeRecommendationLoading.has(task.id)}
                          className="text-xs px-3 py-1.5 rounded-lg bg-indigo-100 text-indigo-700 hover:bg-indigo-200 font-medium transition-colors disabled:opacity-60"
                        >
                          {timeRecommendationLoading.has(task.id) ? "Finding…" : "Suggest time"}
                        </button>
                      )}
                      {task.task_status !== "pending" && (
                        <button onClick={() => resetTask(task.id)}
                          className="text-xs px-3 py-1.5 rounded-lg bg-slate-100 text-slate-500 hover:bg-slate-200 transition-colors">
                          Reset
                        </button>
                      )}
                      {/* Edit button */}
                      <button
                        onClick={() => editingTaskId === task.id ? setEditingTaskId(null) : openEditForm(task)}
                        className={`text-xs px-3 py-1.5 rounded-lg font-medium transition-colors ${
                          editingTaskId === task.id
                            ? "bg-slate-900 text-white"
                            : "bg-slate-100 text-slate-500 hover:bg-slate-200"
                        }`}
                      >Edit</button>
                      <button onClick={() => handleDeleteTask(task.id)}
                        className="text-slate-400 hover:text-rose-500 transition-colors p-1">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                          <path d="M18 6L6 18M6 6l12 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
                        </svg>
                      </button>
                    </div>
                  </div>
                </div>

                {timeRecommendations[task.id] && (
                  <div className="mx-4 mb-4 rounded-2xl border border-indigo-100 bg-indigo-50/60 p-4">
                    <div className="flex items-center justify-between gap-3 mb-3">
                      <div>
                        <div className="text-xs font-semibold text-indigo-900">Suggested times</div>
                        <div className="text-xs text-indigo-700/70">Scored by schedule conflicts and task success probability</div>
                      </div>
                      {timeRecommendations[task.id].status === "accepted" && (
                        <span className="rounded-full bg-indigo-600 px-2 py-1 text-[11px] font-semibold text-white">
                          Saved
                        </span>
                      )}
                      <button
                        onClick={() => setTimeRecommendations((prev) => {
                          const next = { ...prev };
                          delete next[task.id];
                          return next;
                        })}
                        className="text-xs text-indigo-700 hover:text-indigo-900"
                      >Close</button>
                    </div>
                    <div className="grid gap-2 sm:grid-cols-3">
                      {timeRecommendations[task.id].candidates.slice(0, 3).map((candidate) => {
                        const selected = timeRecommendations[task.id].selected_candidate_id === candidate.id;
                        const label = new Date(candidate.candidate_start).toLocaleTimeString([], {
                          hour: "numeric", minute: "2-digit",
                        });
                        return (
                          <div key={candidate.id} className="space-y-1">
                            <button
                              type="button"
                              onClick={() => previewTimeCandidate(task.id, timeRecommendations[task.id], candidate.id)}
                              onDoubleClick={() => chooseTimeCandidate(task.id, timeRecommendations[task.id], candidate.id)}
                              title="Click to select; double-click to save"
                              className={`w-full rounded-xl border px-3 py-2 text-left transition-colors ${
                                selected
                                  ? "border-indigo-500 bg-indigo-600 text-white"
                                  : "border-indigo-100 bg-white text-indigo-900 hover:border-indigo-300"
                              }`}
                            >
                              <div className="flex items-center justify-between gap-2 text-xs font-semibold">
                                <span>#{candidate.rank} · {label}</span>
                                {selected && <span className="text-[10px] uppercase tracking-wide">Selected</span>}
                              </div>
                              <div className={`text-xs mt-0.5 ${selected ? "text-indigo-100" : "text-indigo-700/70"}`}>
                                {Math.round(candidate.predicted_success_probability * 100)}% success
                              </div>
                            </button>
                            <button
                              type="button"
                              onClick={() => chooseTimeCandidate(task.id, timeRecommendations[task.id], candidate.id)}
                              className="w-full rounded-lg border border-indigo-200 bg-white px-2 py-1 text-[11px] font-semibold text-indigo-700 hover:bg-indigo-100"
                            >
                              {selected && timeRecommendations[task.id].status === "accepted" ? "Saved" : "Select"}
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                {/* Inline edit form */}
                {editingTaskId === task.id && (
                  <div className="mx-4 mb-4 bg-slate-50 rounded-2xl border border-slate-200 p-4">
                    <div className="text-xs font-semibold text-slate-600 mb-3">Edit task</div>
                    <div className="grid sm:grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs font-medium text-slate-500 mb-1">Task name</label>
                        <input className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none border border-slate-200 focus:border-slate-400"
                          value={editTitle} onChange={(e) => setEditTitle(e.target.value)}
                          onKeyDown={(e) => e.key === "Enter" && handleSaveEdit()} />
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-slate-500 mb-1">Category</label>
                        <select className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none cursor-pointer border border-slate-200"
                          value={editCategory} onChange={(e) => setEditCategory(e.target.value)}>
                          {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
                        </select>
                      </div>
                    </div>
                    <div className="grid sm:grid-cols-3 gap-3 mt-3">
                      <div>
                        <label className="block text-xs font-medium text-slate-500 mb-1">Date</label>
                        <input type="date" value={editDate} onChange={(e) => setEditDate(e.target.value)}
                          className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none border border-slate-200 cursor-pointer focus:border-slate-400"/>
                      </div>
                      <TimePicker label="Start time" h={editHour} m={editMin} mer={editMer}
                        onH={setEditHour} onM={setEditMin} onMer={setEditMer} />
                      <div>
                        <label className="block text-xs font-medium text-slate-500 mb-1">Duration</label>
                        <select className="w-full bg-white rounded-xl px-3 py-2 text-sm outline-none cursor-pointer border border-slate-200"
                          value={editDuration} onChange={(e) => setEditDuration(e.target.value)}>
                          {[15,30,45,60,90,120].map((m) => <option key={m} value={m}>{m} min</option>)}
                        </select>
                      </div>
                    </div>
                    <div className="mt-3 grid sm:grid-cols-3 gap-3">
                      <RatingDots label="Importance" value={editImportance} onChange={setEditImportance} />
                      <RatingDots label="Energy"     value={editEnergy}     onChange={setEditEnergy} />
                      <RatingDots label="Focus"      value={editFocus}      onChange={setEditFocus} />
                    </div>
                    <div className="mt-3 flex justify-end gap-2">
                      <button onClick={() => setEditingTaskId(null)}
                        className="px-3 py-2 rounded-xl bg-white border border-slate-200 text-sm text-slate-500 hover:bg-slate-50 transition-colors">
                        Cancel
                      </button>
                      <button onClick={handleSaveEdit} disabled={saving}
                        className="px-3 py-2 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors disabled:opacity-60">
                        {saving ? "Saving…" : "Save changes"}
                      </button>
                    </div>
                  </div>
                )}
              </div>
            ))}

            {!loading && tasks.length === 0 && (
              <div className="px-5 py-12 text-center text-sm text-slate-400">
                No tasks for {formatDateLabel(viewDate).toLowerCase()}. Click &quot;+ Add task&quot; to start.
              </div>
            )}
          </div>
        )}
      </div>

      <div className="text-xs text-slate-400 text-center py-2">
        Task data is stored in Supabase and used to train the AI prediction model.
      </div>
    </div>
  );
}
