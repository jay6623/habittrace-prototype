/**
 * HabitTrace API client
 *
 * All functions communicate with the FastAPI backend at NEXT_PUBLIC_API_URL
 * (defaults to http://localhost:8000). Trailing slashes are stripped.
 *
 * Auth:
 *   - If Supabase is configured and the user is signed in, the session JWT is
 *     sent as `Authorization: Bearer <token>`.
 *   - Otherwise, a demo user ID is sent via `X-User-Id` so the backend still
 *     works for local development without auth configured.
 */

import { supabase } from "./supabase";

function normalizeApiBaseUrl(url: string): string {
  return url.trim().replace(/\/+$/, "");
}

const API_URL = normalizeApiBaseUrl(
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000"
);

// ── Types mirroring the backend schemas ────────────────────────────────────

export interface Task {
  id: string;
  user_id: string;
  title: string;
  task_category: string;
  planned_start_time: string;
  planned_date: string;
  planned_duration_min: number;
  importance: number;
  energy_level: number;
  focus_level: number;
  total_tasks_today: number;
  task_status: "pending" | "success" | "failed";
  created_at: string;
  prediction?: Prediction;
}

export interface TaskCreate {
  title: string;
  task_category: string;
  planned_start_time: string;
  planned_date?: string;
  planned_duration_min: number;
  importance: number;
  energy_level: number;
  focus_level: number;
  total_tasks_today: number;
}

export interface ExecutionCreate {
  task_id: string;
  actual_start_time: string;
  actual_end_time: string;
  interruption_count: number;
  stopped_early: boolean;
  task_status: "success" | "failed";
  failure_reason?: string;
}

export interface PredictRequest {
  task_category: string;
  planned_start_time: string;
  planned_date?: string;
  planned_duration_min: number;
  importance: number;
  energy_level: number;
  focus_level: number;
  total_tasks_today: number;
  user_id?: string;
}

export interface Prediction {
  success_probability: number;
  personalized: boolean;
  predicted_failure_reason: string | null;
  failure_probabilities: Record<string, number>;
  top_positive_factors: { feature: string; contribution: number; value: number }[];
  top_negative_factors: { feature: string; contribution: number; value: number }[];
}

export interface AnalyticsSummary {
  period: string;
  total_tasks: number;
  success_rate: number;
  total_planned_minutes: number;
  avg_importance: number;
  avg_interruptions: number;
  most_failed_category: string;
  best_time_of_day: string;
  failure_by_category: Record<string, number>;
  failure_by_reason: Record<string, number>;
  execution_trend: { label: string; planned_mins: number; completed_mins: number; success_rate: number }[];
  success_by_hour: Record<string, number>;
}

export interface TaskSummary {
  id: string;
  title: string;
  task_category: string;
  task_status: "pending" | "success" | "failed";
  planned_start_time: string;
  planned_duration_min: number;
  predicted_success: number | null;
}

export interface PlanHealth {
  overall_success_probability: number;
  task_count: number;
  risks: { level: string; title: string; detail: string }[];
  tasks: TaskSummary[];
}

// ── Auth headers ────────────────────────────────────────────────────────────

async function buildHeaders(): Promise<HeadersInit> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };

  try {
    const {
      data: { session },
    } = await supabase.auth.getSession();

    if (session?.access_token) {
      headers["Authorization"] = `Bearer ${session.access_token}`;
      return headers;
    }
  } catch {
    // Supabase not configured or call failed — fall through to demo mode
  }

  // Demo / development: use a stable ID stored in localStorage
  if (typeof window !== "undefined") {
    let demoId = localStorage.getItem("habittrace_demo_user_id");
    if (!demoId) {
      demoId = `demo-${Math.random().toString(36).slice(2, 10)}`;
      localStorage.setItem("habittrace_demo_user_id", demoId);
    }
    headers["X-User-Id"] = demoId;
  } else {
    headers["X-User-Id"] = "demo-user";
  }

  return headers;
}

// ── Generic fetch wrapper ───────────────────────────────────────────────────

async function apiFetch<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const headers = await buildHeaders();
  const res = await fetch(`${API_URL}${path}`, {
    ...options,
    headers: { ...headers, ...(options.headers ?? {}) },
  });

  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    throw new Error(`API ${options.method ?? "GET"} ${path} → ${res.status}: ${text}`);
  }

  // 204 No Content
  if (res.status === 204) return undefined as T;

  return res.json() as Promise<T>;
}

// ── Tasks ────────────────────────────────────────────────────────────────────

export async function getTasks(date?: string): Promise<Task[]> {
  const qs = date ? `?date=${date}` : "";
  return apiFetch<Task[]>(`/tasks${qs}`);
}

export async function createTask(task: TaskCreate): Promise<Task> {
  return apiFetch<Task>("/tasks", {
    method: "POST",
    body: JSON.stringify(task),
  });
}

export interface TaskUpdate {
  title?: string;
  task_category?: string;
  planned_start_time?: string;
  planned_date?: string;
  planned_duration_min?: number;
  importance?: number;
  energy_level?: number;
  focus_level?: number;
}

export async function updateTask(taskId: string, update: TaskUpdate): Promise<Task> {
  return apiFetch<Task>(`/tasks/${taskId}`, {
    method: "PATCH",
    body: JSON.stringify(update),
  });
}

export async function deleteTask(taskId: string): Promise<void> {
  return apiFetch<void>(`/tasks/${taskId}`, { method: "DELETE" });
}

// ── Executions ───────────────────────────────────────────────────────────────

export async function logExecution(execution: ExecutionCreate): Promise<void> {
  return apiFetch<void>("/executions", {
    method: "POST",
    body: JSON.stringify(execution),
  });
}

// ── Predictions ──────────────────────────────────────────────────────────────

export async function predict(req: PredictRequest): Promise<Prediction> {
  return apiFetch<Prediction>("/predict", {
    method: "POST",
    body: JSON.stringify(req),
  });
}

// ── Analytics ────────────────────────────────────────────────────────────────

export async function getAnalyticsSummary(
  period: "week" | "month" | "3months" = "week"
): Promise<AnalyticsSummary> {
  return apiFetch<AnalyticsSummary>(`/analytics/summary?period=${period}`);
}

export async function getPlanHealth(): Promise<PlanHealth> {
  return apiFetch<PlanHealth>("/analytics/plan-health");
}

// ── Chat (streaming SSE) ─────────────────────────────────────────────────────

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export type ChatStreamEvent =
  | { type: "token"; token: string }
  | { type: "task_candidate"; task: TaskCreate };

/**
 * Streams AI coach response events (tokens + optional task_candidate) via SSE.
 */
export async function* streamChatEvents(
  message: string,
  history: ChatMessage[]
): AsyncGenerator<ChatStreamEvent> {
  const headers = await buildHeaders();
  const res = await fetch(`${API_URL}/chat`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ message, history }),
  });

  if (!res.ok || !res.body) {
    throw new Error(`Chat API error ${res.status}`);
  }

  const reader  = res.body.getReader();
  const decoder = new TextDecoder();
  let   buffer  = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (!line.startsWith("data: ")) continue;
      const data = line.slice(6).trim();
      if (data === "[DONE]") return;
      try {
        const parsed = JSON.parse(data);
        if (parsed.error) throw new Error(parsed.error);
        if (parsed.token) yield { type: "token", token: parsed.token as string };
        if (parsed.task_candidate) yield { type: "task_candidate", task: parsed.task_candidate as TaskCreate };
      } catch (e) {
        if (e instanceof SyntaxError) continue;
        throw e;
      }
    }
  }
}

/** @deprecated use streamChatEvents */
export async function* streamChat(
  message: string,
  history: ChatMessage[]
): AsyncGenerator<string> {
  for await (const event of streamChatEvents(message, history)) {
    if (event.type === "token") yield event.token;
  }
}

// ── Health ───────────────────────────────────────────────────────────────────

export async function getHealth(): Promise<{
  status: string;
  ml_models_loaded: boolean;
  supabase_configured: boolean;
}> {
  return fetch(`${API_URL}/health`).then((r) => r.json());
}
