"use client";
import { useState } from "react";
import Link from "next/link";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";
import { exportAccount } from "@/lib/api";
import { readPreferences } from "@/lib/preferences";
import { useToast } from "@/components/ui/toast";
import { syncProfileDisplayName } from "@/lib/profile";
import { notifyDataChanged } from "@/lib/refresh";
export default function SettingsPage() {
  const { user, displayName } = useAuth();
  if (!user) return null;
  return (
    <Settings
      key={user.id}
      userId={user.id}
      displayName={displayName}
      metadata={user.user_metadata}
      email={user.email ?? ""}
    />
  );
}
function Settings({
  userId,
  displayName,
  metadata,
  email,
}: {
  userId: string;
  displayName: string;
  metadata: Record<string, unknown>;
  email: string;
}) {
  const toast = useToast();
  const [name, setName] = useState(displayName);
  const [preferences, setPreferences] = useState(() =>
    readPreferences(metadata),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!name.trim()) { setError("Enter a display name."); return; }
    if (preferences.workEnd <= preferences.workStart) {
      setError("Planning hours must end after they start.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const nextName = name.trim();
      const { error } = await supabase.auth.updateUser({
        data: { first_name: nextName, planning_preferences: preferences },
      });
      if (error) throw error;
      await syncProfileDisplayName(userId, nextName);
      notifyDataChanged();
      toast.success(
        "Settings saved",
        "Your name and planning preferences are updated.",
      );
    } catch {
      setError("Couldn’t save your settings. Your changes are still here.");
    } finally {
      setBusy(false);
    }
  }
  async function download() {
    if (busy) return;
    setBusy(true);
    try {
      const records = await exportAccount();
      const url = URL.createObjectURL(
        new Blob(
          [
            JSON.stringify(
              {
                ...records,
                profile: {
                  name: displayName,
                  email,
                  preferences: readPreferences(metadata),
                },
              },
              null,
              2,
            ),
          ],
          { type: "application/json" },
        ),
      );
      const a = document.createElement("a");
      a.href = url;
      a.download = `habittrace-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success(
        "Export downloaded",
        "Includes your saved plans and execution records.",
      );
    } catch {
      toast.error(
        "Export failed",
        "No incomplete export was downloaded. Please try again.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="max-w-3xl space-y-6">
      <header>
        <h1 className="text-3xl font-bold">Your preferences</h1>
        <p className="mt-2 text-slate-500">Make planning fit your day.</p>
      </header>
      <form onSubmit={save} className="panel space-y-5">
        <h2 className="text-lg font-semibold">Profile & planning</h2>
        <label className="block text-sm font-medium">
          Display name
          <input
            required
            maxLength={80}
            className="field mt-2"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <p className="text-sm text-slate-500">Signed in as {email}</p>
        <label className="block text-sm font-medium">
          Default plan duration (minutes)
          <input
            required
            type="number"
            min={5}
            max={480}
            className="field mt-2"
            value={preferences.defaultDuration}
            onChange={(e) =>
              setPreferences((p) => ({
                ...p,
                defaultDuration: Number(e.target.value),
              }))
            }
          />
        </label>
        <div className="grid grid-cols-2 gap-4">
          <label className="text-sm font-medium">
            Planning starts
            <input
              required
              type="time"
              className="field mt-2"
              value={preferences.workStart}
              onChange={(e) =>
                setPreferences((p) => ({ ...p, workStart: e.target.value }))
              }
            />
          </label>
          <label className="text-sm font-medium">
            Planning ends
            <input
              required
              type="time"
              className="field mt-2"
              value={preferences.workEnd}
              onChange={(e) =>
                setPreferences((p) => ({ ...p, workEnd: e.target.value }))
              }
            />
          </label>
        </div>
        <p className="text-sm text-slate-500">
          Times use your device’s time zone:{" "}
          {Intl.DateTimeFormat().resolvedOptions().timeZone}.
        </p>
        {error && (
          <p role="alert" className="text-sm text-rose-700">
            {error}
          </p>
        )}
        <button disabled={busy} className="btn-primary" type="submit">
          {busy ? "Working…" : "Save preferences"}
        </button>
      </form>
      <section className="panel">
        <h2 className="text-lg font-semibold">Connected calendars</h2>
        <p className="my-3 text-sm text-slate-500">
          Choose whether to send your plans to Google Calendar. Importing
          external events is not currently supported.
        </p>
        <Link className="btn-secondary" href="/dashboard/integrations">
          Manage connections
        </Link>
      </section>
      <section className="panel">
        <h2 className="text-lg font-semibold">Your records</h2>
        <p className="my-3 text-sm text-slate-500">
          Download your personal plans, execution history and saved profile
          preferences as JSON. Group and AI research records are not included in
          this export.
        </p>
        <button
          className="btn-secondary"
          disabled={busy}
          onClick={() => void download()}
        >
          Download records
        </button>
      </section>
      <section className="panel">
        <h2 className="text-lg font-semibold">Feature availability</h2>
        <p className="mt-3 text-sm leading-relaxed text-slate-600">
          Push reminders, dark mode and self-service account deletion are not
          available yet. No notification or theme settings are applied in the
          background.
        </p>
      </section>
      <button
        className="btn-secondary !text-rose-700"
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          const { error } = await supabase.auth.signOut();
          if (error) {
            toast.error("Couldn’t sign out");
            setBusy(false);
          }
        }}
      >
        Sign out
      </button>
    </div>
  );
}
