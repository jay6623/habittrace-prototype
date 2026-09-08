/**
 * Presentation helpers for Group Scheduling. Pure functions only.
 */

import { ApiError, type GroupMember, type GroupTask } from "./api";

export const INVITE_CODE_LENGTH = 8;
export const INVITE_CODE_PATTERN = /^[A-Z0-9]{8}$/;
export const GROUP_NAME_MAX_LENGTH = 80;
export const GROUP_TASK_TITLE_MAX_LENGTH = 200;

/** Uppercase, drop anything that is not a letter or digit, cap at 8 characters. */
export function normalizeInviteCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, INVITE_CODE_LENGTH);
}

export function memberName(
  member: Pick<GroupMember, "user_id" | "display_name">,
  currentUserId?: string | null
): string {
  const base = member.display_name?.trim() || `Member ${member.user_id.slice(0, 6)}`;
  return member.user_id === currentUserId ? `${base} (You)` : base;
}

export function memberInitial(name: string): string {
  return name.trim().charAt(0).toUpperCase() || "?";
}

/** "2026-09-07" → "Sep 7". Parsed by parts so the local timezone cannot shift the day. */
export function formatDueDate(value: string | null): string | null {
  if (!value) return null;
  const [year, month, day] = value.split("-").map(Number);
  if (!year || !month || !day) return value;
  return new Date(year, month - 1, day).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

/** "14:00:00" → "2:00 PM". */
export function formatDueTime(value: string | null): string | null {
  if (!value) return null;
  const [hourText, minuteText] = value.split(":");
  const hour = Number(hourText);
  const minute = Number(minuteText);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return value;
  const suffix = hour >= 12 ? "PM" : "AM";
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${hour12}:${String(minute).padStart(2, "0")} ${suffix}`;
}

export function formatDue(task: Pick<GroupTask, "due_date" | "due_time">): string | null {
  const parts = [formatDueDate(task.due_date), formatDueTime(task.due_time)].filter(Boolean);
  return parts.length ? parts.join(" · ") : null;
}

/**
 * Turn a thrown value into copy a person can act on. Backend `detail` strings
 * are already written for end users, so they are shown when present.
 */
export function describeApiError(caught: unknown, fallback: string): string {
  if (caught instanceof ApiError) {
    if (caught.status === 401) return "Your session has expired. Please sign in again.";
    if (caught.status === 403) return caught.detail ?? "Only the group owner can do that.";
    if (caught.status === 503) return "The server is temporarily unavailable. Try again shortly.";
    if (caught.detail) return caught.detail;
    return fallback;
  }
  if (caught instanceof Error) {
    const message = caught.message.toLowerCase();
    if (message.includes("failed to fetch") || message.includes("fetch")) {
      return "We couldn't connect. Check your network and try again.";
    }
    if (message.includes("sign in") || message.includes("session")) {
      return "Your session has expired. Please sign in again.";
    }
  }
  return fallback;
}

export function selectedGroupStorageKey(userId: string): string {
  return `habittrace.group.selected.${userId}`;
}

export function readStoredGroupId(userId: string): string | null {
  try {
    return window.localStorage.getItem(selectedGroupStorageKey(userId));
  } catch {
    return null;
  }
}

export function storeGroupId(userId: string, groupId: string | null): void {
  try {
    const key = selectedGroupStorageKey(userId);
    if (groupId) window.localStorage.setItem(key, groupId);
    else window.localStorage.removeItem(key);
  } catch {
    // Storage can be unavailable (private mode, blocked site data); selection is a convenience.
  }
}
