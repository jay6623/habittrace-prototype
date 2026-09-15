"use client";

import { useEffect, useRef, useState } from "react";

import { useAuth } from "@/app/providers";
import { useToast } from "@/components/ui/toast";
import {
  connectGoogleCalendar,
  disconnectGoogleCalendar,
  getGoogleCalendarStatus,
  syncGoogleCalendar,
} from "@/lib/api";
import { getOAuthRedirectBaseUrl } from "@/lib/site";
import { supabase } from "@/lib/supabase";

/**
 * Calendar authorization reuses `signInWithOAuth`, which is a full sign-in:
 * whatever Google account completes it becomes the active Supabase session.
 * Remember who started the flow so a different Google account cannot silently
 * replace the signed-in HabitTrace user when the browser comes back.
 */
const CALENDAR_EXPECTED_USER_KEY = "habittrace.calendar.expected_user";

function rememberCalendarUser(userId: string): void {
  try {
    window.localStorage.setItem(CALENDAR_EXPECTED_USER_KEY, userId);
  } catch {
    // Storage unavailable: the callback will refuse to connect rather than guess.
  }
}

function takeCalendarUser(): string | null {
  try {
    const value = window.localStorage.getItem(CALENDAR_EXPECTED_USER_KEY);
    window.localStorage.removeItem(CALENDAR_EXPECTED_USER_KEY);
    return value;
  } catch {
    return null;
  }
}

// ── Types ──────────────────────────────────────────────────────────────────
interface Integration {
  id: string;
  name: string;
  description: string;
  category: string;
  connected: boolean;
  icon: string; // emoji fallback
  comingSoon?: boolean;
}

// ── Integration list ──────────────────────────────────────────────────────
const INTEGRATIONS: Integration[] = [
  {
    id: "google-calendar",
    name: "Google Calendar",
    description:
      "Sync tasks with your Google Calendar. Tasks appear as calendar events automatically.",
    category: "Calendar",
    connected: false,
    icon: "📅",
  },
  {
    id: "apple-calendar",
    name: "Apple Calendar",
    description:
      "Import events from Apple Calendar and track them as tasks in HabitTrace.",
    category: "Calendar",
    connected: false,
    icon: "🗓",
    comingSoon: true,
  },
  {
    id: "notion",
    name: "Notion",
    description:
      "Pull tasks from your Notion databases and sync completion status back.",
    category: "Productivity",
    connected: false,
    icon: "📝",
    comingSoon: true,
  },
  {
    id: "slack",
    name: "Slack",
    description:
      "Get reminders in Slack before tasks start and celebrate completions with your team.",
    category: "Communication",
    connected: false,
    icon: "💬",
    comingSoon: true,
  },
  {
    id: "todoist",
    name: "Todoist",
    description:
      "Two-way sync with Todoist — create tasks in either app and they stay in sync.",
    category: "Productivity",
    connected: false,
    icon: "✅",
    comingSoon: true,
  },
  {
    id: "github",
    name: "GitHub",
    description:
      "Create tasks from GitHub issues and link PRs to completed work sessions.",
    category: "Development",
    connected: false,
    icon: "🐙",
    comingSoon: true,
  },
  {
    id: "apple-health",
    name: "Apple Health",
    description:
      "Import sleep and activity data to improve HabitTrace's AI energy predictions.",
    category: "Health",
    connected: false,
    icon: "❤️",
    comingSoon: true,
  },
  {
    id: "zapier",
    name: "Zapier",
    description: "Connect HabitTrace to 5,000+ apps via Zapier automations.",
    category: "Automation",
    connected: false,
    icon: "⚡",
    comingSoon: true,
  },
];

const CATEGORIES = [
  "All",
  "Calendar",
  "Productivity",
  "Communication",
  "Development",
  "Health",
  "Automation",
];

// ── Component ──────────────────────────────────────────────────────────────
export default function IntegrationsPage() {
  const [integrations, setIntegrations] = useState(INTEGRATIONS);
  const [activeCategory, setActiveCategory] = useState("All");
  const [connecting, setConnecting] = useState<string | null>(null);
  const [calendarConfigured, setCalendarConfigured] = useState(true);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const initialized = useRef(false);
  const { user } = useAuth();
  const toast = useToast();

  function setGoogleConnected(connected: boolean) {
    setIntegrations((prev) =>
      prev.map((integration) =>
        integration.id === "google-calendar"
          ? { ...integration, connected }
          : integration,
      ),
    );
  }

  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;

    async function initializeCalendar() {
      setConnecting("google-calendar");
      setError(null);
      try {
        const params = new URLSearchParams(window.location.search);
        if (params.get("google_calendar") === "callback") {
          const expectedUserId = takeCalendarUser();
          const {
            data: { session },
            error: sessionError,
          } = await supabase.auth.getSession();
          if (sessionError) throw sessionError;

          if (!expectedUserId) {
            window.history.replaceState({}, "", window.location.pathname);
            throw new Error(
              "We couldn't confirm which HabitTrace account started this connection. Please connect again.",
            );
          }
          if (!session || session.user.id !== expectedUserId) {
            // Google completed the flow as a different account, and Supabase
            // has already swapped the active session to that user. Drop it
            // locally so the original user is asked to sign in again rather
            // than silently continuing as someone else. The dashboard layout
            // redirects to the login page once the session is gone.
            window.history.replaceState({}, "", window.location.pathname);
            toast.error(
              "Calendar not connected",
              "That Google account belongs to a different HabitTrace user. Sign in again and choose the Google account that matches this one.",
              10_000,
            );
            await supabase.auth.signOut({ scope: "local" });
            return;
          }
          if (!session.provider_token) {
            throw new Error(
              "Google did not return Calendar access. Please connect again and approve Calendar permission.",
            );
          }

          const connected = await connectGoogleCalendar({
            providerToken: session.provider_token,
            providerRefreshToken: session.provider_refresh_token ?? undefined,
            timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
          });
          setGoogleConnected(true);
          setNotice(
            `Google Calendar connected. ${connected.sync.synced} task${connected.sync.synced === 1 ? "" : "s"} synced.`,
          );
          window.history.replaceState({}, "", window.location.pathname);
        }

        const status = await getGoogleCalendarStatus();
        setCalendarConfigured(status.configured);
        setGoogleConnected(status.connected);
        if (status.last_error) setError(status.last_error);
      } catch (caught) {
        setError(
          caught instanceof Error
            ? caught.message
            : "Google Calendar setup failed.",
        );
      } finally {
        setConnecting(null);
      }
    }

    void initializeCalendar();
  }, [toast]);

  const filtered =
    activeCategory === "All"
      ? integrations
      : integrations.filter((i) => i.category === activeCategory);

  const connectedCount = integrations.filter((i) => i.connected).length;

  async function handleConnect(id: string) {
    const intg = integrations.find((i) => i.id === id);
    if (!intg || intg.comingSoon) return;

    setConnecting(id);
    setError(null);
    setNotice(null);
    try {
      if (id !== "google-calendar") return;
      if (intg.connected) {
        await disconnectGoogleCalendar();
        setGoogleConnected(false);
        setNotice(
          "Google Calendar disconnected. Existing Google events were left unchanged.",
        );
        return;
      }
      if (!calendarConfigured) {
        throw new Error(
          "Google Calendar environment variables are missing on the backend.",
        );
      }

      if (!user) throw new Error("You need to sign in.");
      rememberCalendarUser(user.id);

      const redirectTo = `${getOAuthRedirectBaseUrl()}/dashboard/integrations?google_calendar=callback`;
      const { error: oauthError } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          scopes: "https://www.googleapis.com/auth/calendar.events",
          redirectTo,
          queryParams: {
            access_type: "offline",
            prompt: "consent",
            include_granted_scopes: "true",
            // Pre-select the signed-in user's Google account. This is a hint
            // only; the callback above verifies the identity that came back.
            ...(user.email ? { login_hint: user.email } : {}),
          },
        },
      });
      if (oauthError) throw oauthError;
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Google Calendar request failed.",
      );
    } finally {
      setConnecting(null);
    }
  }

  async function handleSync() {
    setConnecting("google-calendar");
    setError(null);
    setNotice(null);
    try {
      const result = await syncGoogleCalendar();
      setNotice(
        `${result.synced} task${result.synced === 1 ? "" : "s"} synced to Google Calendar.`,
      );
      if (result.failed) {
        setError(
          `${result.failed} task${result.failed === 1 ? "" : "s"} could not be synced.`,
        );
      }
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : "Calendar sync failed.",
      );
    } finally {
      setConnecting(null);
    }
  }

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <div className="text-sm text-slate-500">Integrations</div>
        <h1 className="text-2xl font-bold">Connected Apps</h1>
      </div>

      {notice && (
        <div
          className="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800"
          role="status"
        >
          {notice}
        </div>
      )}
      {error && (
        <div
          className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
          role="alert"
        >
          {error}
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Connected</div>
          <div className="text-2xl font-bold mt-1 text-emerald-600">
            {connectedCount}
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Available</div>
          <div className="text-2xl font-bold mt-1">
            {INTEGRATIONS.filter((i) => !i.comingSoon).length}
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Coming soon</div>
          <div className="text-2xl font-bold mt-1">
            {INTEGRATIONS.filter((i) => i.comingSoon).length}
          </div>
        </div>
      </div>

      {/* Category filter */}
      <div className="flex flex-wrap gap-2">
        {CATEGORIES.map((cat) => (
          <button
            key={cat}
            onClick={() => setActiveCategory(cat)}
            className={`px-3 py-1.5 rounded-xl text-sm font-medium transition-colors ${
              activeCategory === cat
                ? "bg-slate-900 text-white"
                : "bg-white border border-slate-200 text-slate-600 hover:bg-slate-50"
            }`}
          >
            {cat}
          </button>
        ))}
      </div>

      {/* Integration cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
        {filtered.map((intg) => (
          <div
            key={intg.id}
            className={`bg-white rounded-2xl border p-5 transition-all ${
              intg.connected ? "border-emerald-200" : "border-slate-200"
            }`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="h-11 w-11 rounded-xl bg-slate-100 grid place-items-center text-2xl shrink-0">
                  {intg.icon}
                </div>
                <div>
                  <div className="font-semibold text-sm flex items-center gap-1.5">
                    {intg.name}
                    {intg.comingSoon && (
                      <span className="text-xs px-1.5 py-0.5 rounded-full bg-slate-100 text-slate-500 font-normal">
                        Soon
                      </span>
                    )}
                    {intg.connected && (
                      <span className="text-xs px-1.5 py-0.5 rounded-full bg-emerald-100 text-emerald-700 font-normal">
                        Connected
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-slate-400 mt-0.5">
                    {intg.category}
                  </div>
                </div>
              </div>
            </div>

            <p className="text-sm text-slate-500 mt-3 leading-relaxed">
              {intg.description}
            </p>

            <button
              onClick={() => void handleConnect(intg.id)}
              disabled={
                !!intg.comingSoon ||
                connecting === intg.id ||
                (intg.id === "google-calendar" &&
                  !calendarConfigured &&
                  !intg.connected)
              }
              className={`mt-4 w-full py-2.5 rounded-xl text-sm font-semibold transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
                intg.connected
                  ? "bg-emerald-50 text-emerald-700 hover:bg-rose-50 hover:text-rose-700 border border-emerald-200"
                  : intg.comingSoon
                    ? "bg-slate-50 text-slate-400 border border-slate-200"
                    : "bg-slate-900 text-white hover:bg-slate-800"
              }`}
            >
              {connecting === intg.id
                ? "Connecting…"
                : intg.comingSoon
                  ? "Coming soon"
                  : intg.id === "google-calendar" && !calendarConfigured
                    ? "Backend setup required"
                    : intg.connected
                      ? "Disconnect"
                      : "Connect"}
            </button>
            {intg.id === "google-calendar" && intg.connected && (
              <button
                className="mt-2 w-full rounded-xl border border-slate-200 bg-white py-2.5 text-sm font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
                disabled={connecting === intg.id}
                onClick={() => void handleSync()}
                type="button"
              >
                Sync now
              </button>
            )}
          </div>
        ))}
      </div>

      <div className="text-xs text-slate-400 text-center py-2">
        Suggest an integration →{" "}
        <a
          href="https://support.google.com/calendar/answer/37100"
          target="_blank"
          rel="noreferrer"
          className="underline hover:text-slate-600"
        >
          feedback@habittrace.app
        </a>
      </div>
    </div>
  );
}
