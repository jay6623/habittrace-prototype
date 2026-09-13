/**
 * HabitTrace API client
 *
 * All functions communicate with the FastAPI backend at NEXT_PUBLIC_API_URL
 * (defaults to http://localhost:8000). Trailing slashes are stripped.
 *
 * Auth:
 *   - The signed-in Supabase session JWT is sent as
 *     `Authorization: Bearer <token>`.
 *   - User-owned endpoints never accept a client-supplied user ID; the backend
 *     scopes service-role access to the verified JWT owner.
 */

import { supabase } from "./supabase";
import { notifyDataChanged } from "./refresh";
import { localDateString } from "./mobile-task";

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
  notes?: string | null;
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
  /** AI V2 immutable plan snapshot created for this task, when available. */
  ai_plan_input_id?: string;
  prediction?: Prediction;
}

export interface TaskCreate {
  title: string;
  notes?: string | null;
  task_category: string;
  planned_start_time: string;
  planned_date?: string;
  planned_duration_min: number;
  importance: number;
  energy_level: number;
  focus_level: number;
  total_tasks_today: number;
}

interface AIPlanInputResponse {
  id: string;
}

export interface AIOutcomeInput {
  task: Pick<Task, "ai_plan_input_id" | "planned_date">;
  taskResult: "success" | "failed";
  actualStartTime: string;
  actualEndTime: string;
  interruptionCount: number;
  stoppedEarly: boolean;
  failureReason?: string;
}

interface AIOutcomeResponse {
  id: string;
}

const AI_PLAN_MAP_KEY = "habittrace_ai_plan_ids";
const aiPlanRequests = new Map<string, Promise<string>>();

function readAIPlanMap(): Record<string, string> {
  if (typeof window === "undefined") return {};
  try {
    return JSON.parse(localStorage.getItem(AI_PLAN_MAP_KEY) ?? "{}") as Record<string, string>;
  } catch {
    return {};
  }
}

function rememberAIPlan(taskId: string, planId: string): void {
  if (typeof window === "undefined") return;
  localStorage.setItem(AI_PLAN_MAP_KEY, JSON.stringify({
    ...readAIPlanMap(),
    [taskId]: planId,
  }));
}

function forgetAIPlan(taskId: string): void {
  if (typeof window === "undefined") return;
  const plans = readAIPlanMap();
  delete plans[taskId];
  localStorage.setItem(AI_PLAN_MAP_KEY, JSON.stringify(plans));
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

export interface Execution {
  id: string;
  task_id: string;
  user_id: string;
  actual_start_time: string;
  actual_end_time: string | null;
  interruption_count: number;
  stopped_early: boolean;
  task_status: "success" | "failed" | null;
  failure_reason: string | null;
  created_at: string;
}

export interface ExecutionCompleteInput {
  actual_start_time?: string;
  actual_end_time?: string;
  interruption_count?: number;
  stopped_early?: boolean;
  task_status: "success" | "failed";
  failure_reason?: string;
}

export type MobileOutcomeStatus = "completed" | "partial" | "abandoned";

export interface MobileAIOutcomeInput {
  task: Pick<Task, "ai_plan_input_id" | "planned_date">;
  execution: Pick<Execution, "actual_start_time" | "actual_end_time">;
  outcomeStatus: MobileOutcomeStatus;
  failureReason?: string;
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
  base_success_probability?: number | null;
  personalized: boolean;
  personalization?: PersonalizationSummary;
  predicted_failure_reason: string | null;
  failure_probabilities: Record<string, number>;
  top_positive_factors: { feature: string; contribution: number; value: number }[];
  top_negative_factors: { feature: string; contribution: number; value: number }[];
  explanation?: {
    source?: string;
    factors?: { feature: string; direction: string; value: number; message: string }[];
  };
  recommended_actions?: { code: string; title: string; detail: string }[];
}

export interface PersonalizationSummary {
  applied: boolean;
  sample_count: number;
  confidence: number;
  history_success_rate: number | null;
  factors: {
    type: string;
    direction: "positive" | "negative";
    sample_count: number;
    message: string;
  }[];
}

export interface TimeCandidate {
  id: string;
  recommendation_id: string;
  candidate_start: string;
  candidate_end: string;
  predicted_success_probability: number;
  conflict_penalty: number;
  overload_penalty: number;
  preference_penalty: number;
  final_score: number;
  rank: number;
  reason_snapshot: {
    predicted_failure_reason?: string | null;
    strategy?: string;
    personalization?: PersonalizationSummary;
  };
}

export interface TimeRecommendation {
  id: string;
  plan_input_id: string;
  model_version_id: string;
  earliest_start: string;
  latest_end: string;
  slot_interval_minutes: number;
  minimum_buffer_minutes: number;
  status: "generated" | "accepted" | "modified" | "dismissed" | "expired";
  selected_candidate_id: string | null;
  created_at: string;
  candidates: TimeCandidate[];
}

interface PersistedAIPredictionResponse {
  model_version: string;
  success_probability: number;
  base_success_probability?: number | null;
  personalization?: PersonalizationSummary;
  failure_reason_probabilities: Record<string, number>;
  predicted_failure_reason: string | null;
  explanation?: Prediction["explanation"];
  recommended_actions?: Prediction["recommended_actions"];
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

export interface PersonalizedOutlookTask {
  id: string;
  title: string;
  success_probability: number;
  predicted_failure_reason: string | null;
}

export interface PersonalizedOutlook {
  available: boolean;
  reason: "no_pending_plans" | "model_unavailable" | null;
  date: string | null;
  task_count: number;
  predicted_success_probability: number | null;
  highest_potential: PersonalizedOutlookTask | null;
  needs_attention: PersonalizedOutlookTask | null;
  recommendation: { code: string; title: string; detail: string } | null;
  personalization: PersonalizationSummary;
}

export interface PersonalizedPattern {
  type: "category" | "time_of_day" | "weekday" | "duration";
  label: string;
  direction: "positive" | "negative";
  sample_count: number;
  success_rate: number;
  difference: number;
  message: string;
}

export interface PersonalizedInsights {
  available: boolean;
  reason: "insufficient_data" | null;
  period: "week" | "month" | "3months";
  sample_count: number;
  confidence_label: "learning" | "early" | "moderate" | "strong";
  success_rate: number | null;
  previous_success_rate: number | null;
  change_percentage_points: number | null;
  strongest_pattern: PersonalizedPattern | null;
  pattern_to_watch: PersonalizedPattern | null;
  recommended_experiment: { title: string; detail: string };
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
  } catch (error) {
    throw new Error("We couldn't verify your session. Try again.", {
      cause: error,
    });
  }

  // User-owned endpoints require a verified Supabase identity.
  throw new Error("You need to sign in.");
}

// ── Generic fetch wrapper ───────────────────────────────────────────────────

/**
 * Thrown for non-2xx responses. Still an `Error` with the historical
 * `API <method> <path> → <status>: <body>` message, so existing callers that
 * string-match on the message keep working; new callers can branch on
 * `status` and show the backend's `detail` text directly.
 */
export class ApiError extends Error {
  readonly status: number;
  /** The backend's `detail` string when the body was `{ detail, code }`. */
  readonly detail: string | null;
  /** The backend's machine-readable `code` (e.g. "not_found"), when present. */
  readonly code: string | null;

  constructor(message: string, status: number, detail: string | null, code: string | null) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.detail = detail;
    this.code = code;
  }
}

function parseErrorBody(text: string): { detail: string | null; code: string | null } {
  try {
    const parsed = JSON.parse(text) as { detail?: unknown; code?: unknown };
    return {
      detail: typeof parsed.detail === "string" ? parsed.detail : null,
      code: typeof parsed.code === "string" ? parsed.code : null,
    };
  } catch {
    return { detail: null, code: null };
  }
}

async function apiFetch<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const headers = await buildHeaders();
  const res = await fetch(`${API_URL}${path}`, {
    ...options,
    cache: options.cache ?? "no-store",
    headers: { ...headers, ...(options.headers ?? {}) },
  });

  if (!res.ok) {
    const text = await res.text().catch(() => res.statusText);
    const { detail, code } = parseErrorBody(text);
    throw new ApiError(
      `API ${options.method ?? "GET"} ${path} → ${res.status}: ${text}`,
      res.status,
      detail,
      code
    );
  }

  if (["POST", "PATCH", "PUT", "DELETE"].includes(options.method ?? "GET") && /^\/(tasks|executions|groups)(\/|$)/.test(path)) notifyDataChanged();

  // 204 No Content
  if (res.status === 204) return undefined as T;

  return res.json() as Promise<T>;
}

// ── Google Calendar integration ──────────────────────────────────────────────

export interface GoogleCalendarStatus {
  configured: boolean;
  connected: boolean;
  timezone: string | null;
  last_synced_at: string | null;
  last_error: string | null;
}

export interface GoogleCalendarSyncResult {
  synced: number;
  failed: number;
  errors: string[];
}

export async function getGoogleCalendarStatus(): Promise<GoogleCalendarStatus> {
  return apiFetch<GoogleCalendarStatus>("/integrations/google-calendar/status");
}

export async function connectGoogleCalendar(input: {
  providerToken: string;
  providerRefreshToken?: string;
  timezone: string;
}): Promise<{ status: GoogleCalendarStatus; sync: GoogleCalendarSyncResult }> {
  return apiFetch("/integrations/google-calendar/connect", {
    method: "POST",
    body: JSON.stringify({
      provider_token: input.providerToken,
      provider_refresh_token: input.providerRefreshToken,
      timezone: input.timezone,
    }),
  });
}

export async function syncGoogleCalendar(): Promise<GoogleCalendarSyncResult> {
  return apiFetch<GoogleCalendarSyncResult>("/integrations/google-calendar/sync", {
    method: "POST",
  });
}

export async function disconnectGoogleCalendar(): Promise<void> {
  return apiFetch<void>("/integrations/google-calendar", { method: "DELETE" });
}

// ── Tasks ────────────────────────────────────────────────────────────────────

export async function getTasks(date?: string): Promise<Task[]> {
  const qs = date ? `?date=${date}` : "";
  const tasks = await apiFetch<Task[]>(`/tasks${qs}`);
  const aiPlanMap = readAIPlanMap();
  return tasks.map((task) => ({
    ...task,
    ai_plan_input_id: task.ai_plan_input_id ?? aiPlanMap[task.id],
  }));
}

export async function getTask(taskId: string): Promise<Task> {
  const task = await apiFetch<Task>(`/tasks/${taskId}`);
  const aiPlanMap = readAIPlanMap();
  return {
    ...task,
    ai_plan_input_id: task.ai_plan_input_id ?? aiPlanMap[task.id],
  };
}

export async function createTask(task: TaskCreate): Promise<Task> {
  const created = await apiFetch<Task>("/tasks", {
    method: "POST",
    body: JSON.stringify(task),
  });

  // AI V2 requires a real Supabase user token. Keep legacy/demo task creation
  // independent so an unavailable AI database never breaks the main app.
  try {
    const {
      data: { session },
    } = await supabase.auth.getSession();
    if (!session?.access_token) return created;

    const aiPlan = await apiFetch<AIPlanInputResponse>("/api/v2/ai/plans", {
      method: "POST",
      body: JSON.stringify(toAIPlanInput(task)),
    });
    rememberAIPlan(created.id, aiPlan.id);
    notifyDataChanged();
    return { ...created, ai_plan_input_id: aiPlan.id };
  } catch (error) {
    console.warn("AI V2 plan snapshot was not created:", error);
    return created;
  }
}

/** Create the planning snapshot needed for recommendations on a legacy task. */
export async function ensureAIPlan(task: Task): Promise<string> {
  const existing = task.ai_plan_input_id ?? readAIPlanMap()[task.id];
  if (existing) return existing;

  const inFlight = aiPlanRequests.get(task.id);
  if (inFlight) return inFlight;

  const request = apiFetch<AIPlanInputResponse>("/api/v2/ai/plans", {
    method: "POST",
    body: JSON.stringify(toAIPlanInput(task)),
  })
    .then((plan) => {
      rememberAIPlan(task.id, plan.id);
      return plan.id;
    })
    .finally(() => aiPlanRequests.delete(task.id));

  aiPlanRequests.set(task.id, request);
  return request;
}

/** Create the immutable AI revision corresponding to an edited task. */
export async function reviseAIPlan(
  taskId: string,
  parentPlanInputId: string,
  task: TaskCreate,
): Promise<string> {
  const aiPlan = await apiFetch<AIPlanInputResponse>("/api/v2/ai/plans", {
    method: "POST",
    body: JSON.stringify({
      ...toAIPlanInput(task),
      parent_plan_input_id: parentPlanInputId,
      input_source: "reschedule",
    }),
  });
  rememberAIPlan(taskId, aiPlan.id);
  return aiPlan.id;
}

export function clearAIPlan(taskId: string): void {
  forgetAIPlan(taskId);
}

export async function createAIOutcome(input: AIOutcomeInput): Promise<AIOutcomeResponse | null> {
  const planId = input.task.ai_plan_input_id;
  if (!planId) return null;

  const date = input.task.planned_date ?? localDateString();
  const actualStart = normalizeActualTime(input.actualStartTime, date);
  const actualEnd = normalizeActualTime(input.actualEndTime, date);
  const isSuccess = input.taskResult === "success";

  return persistAIOutcome({
    planId,
    outcomeStatus: isSuccess ? "completed" : "partial",
    actualStart,
    actualEnd,
    completionRatio: isSuccess ? 1 : 0,
    interruptionCount: input.interruptionCount,
    stoppedEarly: input.stoppedEarly,
    failureReason: input.failureReason,
  });
}

export async function createMobileAIOutcome(
  input: MobileAIOutcomeInput,
): Promise<AIOutcomeResponse | null> {
  const planId = input.task.ai_plan_input_id;
  const actualEnd = input.execution.actual_end_time;
  if (!planId || !actualEnd) return null;

  return persistAIOutcome({
    planId,
    outcomeStatus: input.outcomeStatus,
    actualStart: normalizeActualTime(
      input.execution.actual_start_time,
      input.task.planned_date,
    ),
    actualEnd: normalizeActualTime(actualEnd, input.task.planned_date),
    completionRatio:
      input.outcomeStatus === "completed"
        ? 1
        : input.outcomeStatus === "partial"
          ? 0.5
          : 0,
    interruptionCount: 0,
    stoppedEarly: input.outcomeStatus !== "completed",
    failureReason: input.failureReason,
  });
}

interface PersistAIOutcomeInput {
  planId: string;
  outcomeStatus: MobileOutcomeStatus;
  actualStart: string;
  actualEnd: string;
  completionRatio: number;
  interruptionCount: number;
  stoppedEarly: boolean;
  failureReason?: string;
}

async function persistAIOutcome(
  input: PersistAIOutcomeInput,
): Promise<AIOutcomeResponse> {
  const startMs = Date.parse(input.actualStart);
  const endMs = Date.parse(input.actualEnd);
  const activeMinutes = Math.max(0, Math.round((endMs - startMs) / 60000));
  const outcome = await apiFetch<AIOutcomeResponse>(
    `/api/v2/ai/plans/${input.planId}/outcome`,
    {
      method: "POST",
      body: JSON.stringify({
        outcome_status: input.outcomeStatus,
        actual_start: input.actualStart,
        actual_end: input.actualEnd,
        active_minutes: activeMinutes,
        completion_ratio: input.completionRatio,
        interruption_count: input.interruptionCount,
        stopped_early: input.stoppedEarly,
        user_note: null,
      }),
    },
  );

  if (input.outcomeStatus !== "completed" && input.failureReason) {
    await apiFetch(`/api/v2/ai/outcomes/${outcome.id}/failure-reasons`, {
      method: "POST",
      body: JSON.stringify({
        primary_reason_code: toAIReasonCode(input.failureReason),
        secondary_reason_codes: [],
      }),
    });
  }
  return outcome;
}

function toAIReasonCode(reason: string): string {
  const canonicalCodes = new Set([
    "low_readiness",
    "schedule_overload",
    "underestimated_time",
    "interruption",
    "unexpected_event",
    "unclear_plan",
    "task_too_difficult",
    "other",
  ]);
  if (canonicalCodes.has(reason)) return reason;

  const mapping: Record<string, string> = {
    low_energy: "low_readiness",
    low_focus: "low_readiness",
    start_delay: "unclear_plan",
    interruptions: "interruption",
    time_underestimate: "underestimated_time",
    schedule_conflict: "schedule_overload",
    unexpected_event: "unexpected_event",
    other: "other",
  };
  return mapping[reason] ?? "other";
}

function normalizeActualTime(value: string, date: string): string {
  if (value.includes("T")) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
  }
  return parsePlannedStart(value, date);
}

function toAIPlanInput(task: TaskCreate): Record<string, unknown> {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const plannedDate = task.planned_date ?? localDateString();
  const plannedStart = parsePlannedStart(task.planned_start_time, plannedDate);

  return {
    input_source: "user",
    title: task.title,
    description: task.notes?.trim() ? task.notes.trim() : null,
    category: task.task_category,
    planned_start: plannedStart,
    planned_duration_minutes: task.planned_duration_min,
    importance: task.importance,
    difficulty: 3,
    required_energy: task.energy_level,
    required_focus: task.focus_level,
    current_energy: task.energy_level,
    current_focus: task.focus_level,
    sleep_hours: null,
    stress_level: null,
    timezone_name: timezone,
    is_fixed_time: true,
  };
}

function parsePlannedStart(time: string, date: string): string {
  const match = time.trim().match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i);
  if (!match) {
    throw new Error(`Invalid planned_start_time: ${time}`);
  }

  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const meridiem = match[3]?.toUpperCase();
  if (meridiem) {
    if (hour < 1 || hour > 12) throw new Error(`Invalid planned_start_time: ${time}`);
    if (meridiem === "PM" && hour !== 12) hour += 12;
    if (meridiem === "AM" && hour === 12) hour = 0;
  }
  if (hour > 23 || minute > 59) throw new Error(`Invalid planned_start_time: ${time}`);

  const local = new Date(`${date}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00`);
  if (Number.isNaN(local.getTime())) throw new Error(`Invalid planned date: ${date}`);
  return local.toISOString();
}

export interface TaskUpdate {
  title?: string;
  notes?: string | null;
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

export async function logExecution(execution: ExecutionCreate): Promise<Execution> {
  return apiFetch<Execution>("/executions", {
    method: "POST",
    body: JSON.stringify(execution),
  });
}

export async function getActiveExecutions(): Promise<Execution[]> {
  return apiFetch<Execution[]>("/executions?active=true");
}

export async function getExecutions(): Promise<Execution[]> {
  return apiFetch<Execution[]>("/executions");
}

export async function getLatestFinishedExecution(
  taskId: string,
): Promise<Execution | null> {
  const executions = await getExecutions();
  return (
    executions.find(
      (execution) =>
        execution.task_id === taskId && execution.actual_end_time != null,
    ) ?? null
  );
}

export async function startExecution(taskId: string): Promise<Execution> {
  return apiFetch<Execution>("/executions/start", {
    method: "POST",
    body: JSON.stringify({ task_id: taskId }),
  });
}

export async function completeExecution(
  executionId: string,
  input: ExecutionCompleteInput,
): Promise<Execution> {
  return apiFetch<Execution>(`/executions/${executionId}/complete`, {
    method: "PATCH",
    body: JSON.stringify(input),
  });
}

export async function reviseExecution(
  executionId: string,
  input: ExecutionCompleteInput,
): Promise<Execution> {
  return apiFetch<Execution>(`/executions/${executionId}`, {
    method: "PATCH",
    body: JSON.stringify(input),
  });
}

// ── Predictions ──────────────────────────────────────────────────────────────

export async function predict(req: PredictRequest): Promise<Prediction> {
  return apiFetch<Prediction>("/predict", {
    method: "POST",
    body: JSON.stringify(req),
  });
}

/** Run the AI V2 model for an owned plan and persist the prediction in AI DB. */
export async function predictAIPlan(planInputId: string): Promise<Prediction> {
  const result = await apiFetch<PersistedAIPredictionResponse>(
    `/api/v2/ai/plans/${planInputId}/predict`,
    { method: "POST" }
  );
  return {
    success_probability: result.success_probability,
    base_success_probability: result.base_success_probability,
    personalized: result.personalization?.applied ?? false,
    personalization: result.personalization,
    predicted_failure_reason: result.predicted_failure_reason,
    failure_probabilities: result.failure_reason_probabilities,
    top_positive_factors: [],
    top_negative_factors: [],
    explanation: result.explanation,
    recommended_actions: result.recommended_actions,
  };
}

export async function createTimeRecommendation(
  planInputId: string,
  date: string,
  options: {
    earliestTime?: string;
    latestTime?: string;
    slotIntervalMinutes?: number;
    minimumBufferMinutes?: number;
  } = {},
): Promise<TimeRecommendation> {
  return apiFetch<TimeRecommendation>(
    `/api/v2/ai/plans/${planInputId}/time-recommendations`,
    {
      method: "POST",
      body: JSON.stringify({
        earliest_start: parsePlannedStart(options.earliestTime ?? "8:00 AM", date),
        latest_end: parsePlannedStart(options.latestTime ?? "10:00 PM", date),
        slot_interval_minutes: options.slotIntervalMinutes ?? 15,
        minimum_buffer_minutes: options.minimumBufferMinutes ?? 15,
      }),
    },
  );
}

export async function selectTimeCandidate(
  recommendationId: string,
  candidateId: string,
): Promise<TimeRecommendation> {
  return apiFetch<TimeRecommendation>(
    `/api/v2/ai/time-recommendations/${recommendationId}/select`,
    {
      method: "POST",
      body: JSON.stringify({ candidate_id: candidateId, status: "accepted" }),
    },
  );
}

/** Read the latest persisted prediction without creating another database row. */
export async function getAIPlanPrediction(planInputId: string): Promise<Prediction | null> {
  const response = await apiFetch<{ prediction: PersistedAIPredictionResponse | null }>(
    `/api/v2/ai/plans/${planInputId}/prediction`
  );
  if (!response.prediction) return null;
  return {
    success_probability: response.prediction.success_probability,
    base_success_probability: response.prediction.base_success_probability,
    personalized: response.prediction.personalization?.applied ?? false,
    personalization: response.prediction.personalization,
    predicted_failure_reason: response.prediction.predicted_failure_reason,
    failure_probabilities: response.prediction.failure_reason_probabilities,
    top_positive_factors: [],
    top_negative_factors: [],
    explanation: response.prediction.explanation,
    recommended_actions: response.prediction.recommended_actions,
  };
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

export async function getPersonalizedOutlook(): Promise<PersonalizedOutlook> {
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const params = new URLSearchParams({
    date: localDateString(),
    timezone_name: timezone,
  });
  return apiFetch<PersonalizedOutlook>(`/analytics/personalized-outlook?${params}`);
}

export async function getPersonalizedInsights(
  period: "week" | "month" | "3months",
): Promise<PersonalizedInsights> {
  const params = new URLSearchParams({
    period,
    end_date: localDateString(),
  });
  return apiFetch<PersonalizedInsights>(`/analytics/personalized-insights?${params}`);
}

// ── Chat (streaming SSE) ─────────────────────────────────────────────────────

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface CoachTimeOption {
  start: string;
  end: string;
  score: number;
  reasons: string[];
}

export interface CoachProposal {
  id: string;
  task: TaskCreate;
  options: CoachTimeOption[];
}

export interface CoachConversation {
  id: string;
  messages: Array<ChatMessage & { id: string; created_at: string }>;
  pending_proposals: CoachProposal[];
}

export type ChatStreamEvent =
  | { type: "token"; token: string }
  | { type: "conversation"; conversationId: string }
  | { type: "proposal"; proposal: CoachProposal };

/**
 * Streams AI coach response events (tokens + optional task_candidate) via SSE.
 */
export async function* streamChatEvents(
  message: string,
  history: ChatMessage[],
  conversationId?: string,
): AsyncGenerator<ChatStreamEvent> {
  const headers = await buildHeaders();
  const timezoneName = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const res = await fetch(`${API_URL}/chat`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({
      message,
      history,
      conversation_id: conversationId ?? null,
      timezone_name: timezoneName,
    }),
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
        if (parsed.conversation_id) {
          yield { type: "conversation", conversationId: parsed.conversation_id as string };
        }
        if (parsed.proposal) {
          yield { type: "proposal", proposal: parsed.proposal as CoachProposal };
        }
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

export async function getLatestCoachConversation(): Promise<CoachConversation | null> {
  return apiFetch<CoachConversation | null>("/chat/conversations/latest");
}

export async function archiveCoachConversation(conversationId: string): Promise<void> {
  return apiFetch<void>(`/chat/conversations/${conversationId}`, { method: "DELETE" });
}

export async function confirmCoachProposal(
  proposalId: string,
  candidateStart: string,
  task: TaskCreate,
): Promise<Task> {
  return apiFetch<Task>(`/chat/proposals/${proposalId}/confirm`, {
    method: "POST",
    body: JSON.stringify({ candidate_start: candidateStart, task }),
  });
}

export async function dismissCoachProposal(proposalId: string): Promise<void> {
  return apiFetch<void>(`/chat/proposals/${proposalId}/dismiss`, { method: "POST" });
}

// ── Group scheduling ─────────────────────────────────────────────────────────
// Mirrors backend/app/schemas/group.py. Membership is enforced server-side:
// a group the caller does not belong to answers 404 on every route.

export type GroupRole = "owner" | "member";
export type GroupTaskStatus = "pending" | "success" | "failed";
export type GroupTaskPriority = "high" | "medium" | "low";

export interface Group {
  id: string;
  owner_id: string;
  name: string;
  invite_code: string;
  created_at: string;
  /** The signed-in user's role in this group. */
  role: GroupRole;
}

export interface GroupMember {
  user_id: string;
  role: GroupRole;
  joined_at: string;
  display_name: string | null;
}

export interface GroupTask {
  id: string;
  group_id: string;
  created_by: string;
  assigned_to: string | null;
  assignee_name: string | null;
  title: string;
  category: string;
  priority: GroupTaskPriority;
  status: GroupTaskStatus;
  /** ISO date, e.g. "2026-09-07". */
  due_date: string | null;
  /** ISO time, e.g. "14:00:00". */
  due_time: string | null;
  created_at: string;
  updated_at: string;
}

export interface GroupDetail {
  group: Group;
  members: GroupMember[];
  /** Newest first. */
  tasks: GroupTask[];
}

export interface GroupTaskCreate {
  title: string;
  category?: string;
  priority?: GroupTaskPriority;
  due_date?: string | null;
  /** "HH:MM" or "HH:MM:SS". */
  due_time?: string | null;
  assigned_to?: string | null;
}

/** Send only the fields to change; `assigned_to: null` unassigns. */
export interface GroupTaskUpdate {
  title?: string;
  category?: string;
  priority?: GroupTaskPriority;
  status?: GroupTaskStatus;
  due_date?: string | null;
  due_time?: string | null;
  assigned_to?: string | null;
}

export async function getGroups(): Promise<Group[]> {
  return apiFetch<Group[]>("/groups");
}

export async function createGroup(name: string): Promise<Group> {
  return apiFetch<Group>("/groups", {
    method: "POST",
    body: JSON.stringify({ name }),
  });
}

export async function joinGroup(inviteCode: string): Promise<Group> {
  return apiFetch<Group>("/groups/join", {
    method: "POST",
    body: JSON.stringify({ invite_code: inviteCode }),
  });
}

export async function getGroupDetail(groupId: string): Promise<GroupDetail> {
  return apiFetch<GroupDetail>(`/groups/${groupId}`);
}

export async function deleteGroup(groupId: string): Promise<void> {
  return apiFetch<void>(`/groups/${groupId}`, { method: "DELETE" });
}

export async function createGroupTask(
  groupId: string,
  input: GroupTaskCreate
): Promise<GroupTask> {
  return apiFetch<GroupTask>(`/groups/${groupId}/tasks`, {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function updateGroupTask(
  groupId: string,
  taskId: string,
  update: GroupTaskUpdate
): Promise<GroupTask> {
  return apiFetch<GroupTask>(`/groups/${groupId}/tasks/${taskId}`, {
    method: "PATCH",
    body: JSON.stringify(update),
  });
}

export async function deleteGroupTask(groupId: string, taskId: string): Promise<void> {
  return apiFetch<void>(`/groups/${groupId}/tasks/${taskId}`, { method: "DELETE" });
}

// ── Health ───────────────────────────────────────────────────────────────────

export async function getHealth(): Promise<{
  status: string;
  ml_models_loaded: boolean;
  supabase_configured: boolean;
}> {
  return fetch(`${API_URL}/health`).then((r) => r.json());
}


export async function exportAccount(): Promise<{ exported_at: string; scope: string; tasks: Task[]; executions: Execution[] }> {
  return apiFetch("/account/export");
}
