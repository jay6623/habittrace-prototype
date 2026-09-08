"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";
import { useToast } from "@/components/ui/toast";

// ── Toggle component ──────────────────────────────────────────────────────
function Toggle({
  checked,
  onChange,
}: {
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <button
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-6 w-11 shrink-0 rounded-full transition-colors ${
        checked ? "bg-slate-900" : "bg-slate-200"
      }`}
    >
      <span
        className={`inline-block h-5 w-5 rounded-full bg-white shadow transition-transform mt-0.5 ${
          checked ? "translate-x-5" : "translate-x-0.5"
        }`}
      />
    </button>
  );
}

// ── Component ─────────────────────────────────────────────────────────────
export default function SettingsPage() {
  const { user, displayName } = useAuth();
  const router = useRouter();
  const toast = useToast();

  // Profile
  const [name, setName]       = useState(displayName);
  const [saving, setSaving]   = useState(false);
  const [savedMsg, setSavedMsg] = useState("");

  // Notifications
  const [notifyBefore, setNotifyBefore]   = useState(true);
  const [notifySuccess, setNotifySuccess] = useState(true);
  const [notifyWeekly, setNotifyWeekly]   = useState(false);
  const [notifyAI, setNotifyAI]           = useState(true);
  const [notifyGroup, setNotifyGroup]     = useState(true);

  // Preferences
  const [defaultDuration, setDefaultDuration] = useState("60");
  const [workStart, setWorkStart]             = useState("09:00");
  const [workEnd, setWorkEnd]                 = useState("22:00");
  const [theme, setTheme]                     = useState<"system" | "light" | "dark">("system");

  // Data
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deleteInput, setDeleteInput]             = useState("");

  async function handleSaveProfile() {
    setSaving(true);
    try {
      // Update Supabase user metadata if available
      if (user) {
        await supabase.auth.updateUser({
          data: { first_name: name },
        });
      }
      setSavedMsg("Saved!");
      setTimeout(() => setSavedMsg(""), 2500);
    } catch {
      setSavedMsg("Failed to save — try again.");
      setTimeout(() => setSavedMsg(""), 3000);
    } finally {
      setSaving(false);
    }
  }

  async function handleLogout() {
    try { await supabase.auth.signOut(); } catch { /* ignore */ }
    router.push("/login");
  }

  function handleExport() {
    const data = {
      exported_at: new Date().toISOString(),
      user_email: user?.email ?? "demo",
      note: "Full task export requires backend API — connect backend to download your data.",
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement("a");
    a.href = url;
    a.download = "habittrace_export.json";
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="space-y-6 max-w-2xl">
      {/* Header */}
      <div>
        <div className="text-sm text-slate-500">Settings</div>
        <h1 className="text-2xl font-bold">Account Settings</h1>
      </div>

      {/* ── Profile ──────────────────────────────────────────────────────── */}
      <section className="bg-white rounded-2xl border border-slate-200 p-5">
        <div className="font-semibold mb-4">Profile</div>

        <div className="flex items-center gap-4 mb-5">
          <div className="h-16 w-16 rounded-full bg-slate-900 text-white grid place-items-center text-xl font-bold shrink-0">
            {name.charAt(0).toUpperCase()}
          </div>
          <div>
            <div className="font-medium">{displayName}</div>
            <div className="text-sm text-slate-500">{user?.email ?? "Demo mode"}</div>
          </div>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1.5">Display name</label>
            <input
              className="w-full bg-slate-100 rounded-xl px-4 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1.5">Email</label>
            <input
              className="w-full bg-slate-50 rounded-xl px-4 py-2.5 text-sm outline-none text-slate-400 cursor-not-allowed"
              value={user?.email ?? "demo@habittrace.app"}
              readOnly
            />
            <div className="text-xs text-slate-400 mt-1">Email cannot be changed here.</div>
          </div>
        </div>

        <div className="mt-4 flex items-center gap-3">
          <button
            onClick={handleSaveProfile}
            disabled={saving}
            className="px-4 py-2 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors disabled:opacity-60"
          >
            {saving ? "Saving…" : "Save changes"}
          </button>
          {savedMsg && (
            <span className={`text-sm ${savedMsg.startsWith("Failed") ? "text-rose-500" : "text-emerald-600"}`}>
              {savedMsg}
            </span>
          )}
        </div>
      </section>

      {/* ── Scheduling Preferences ───────────────────────────────────────── */}
      <section className="bg-white rounded-2xl border border-slate-200 p-5">
        <div className="font-semibold mb-4">Scheduling preferences</div>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1.5">Default task duration</label>
            <select
              className="w-full bg-slate-100 rounded-xl px-4 py-2.5 text-sm outline-none cursor-pointer"
              value={defaultDuration}
              onChange={(e) => setDefaultDuration(e.target.value)}
            >
              {[15, 30, 45, 60, 90, 120].map((m) => (
                <option key={m} value={m}>{m} min</option>
              ))}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium mb-1.5">Work day start</label>
              <input
                type="time"
                className="w-full bg-slate-100 rounded-xl px-4 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
                value={workStart}
                onChange={(e) => setWorkStart(e.target.value)}
              />
            </div>
            <div>
              <label className="block text-sm font-medium mb-1.5">Work day end</label>
              <input
                type="time"
                className="w-full bg-slate-100 rounded-xl px-4 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
                value={workEnd}
                onChange={(e) => setWorkEnd(e.target.value)}
              />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium mb-2">Theme</label>
            <div className="flex gap-2">
              {(["system", "light", "dark"] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setTheme(t)}
                  className={`px-4 py-2 rounded-xl text-sm font-medium capitalize transition-colors ${
                    theme === t
                      ? "bg-slate-900 text-white"
                      : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ── Notifications ────────────────────────────────────────────────── */}
      <section className="bg-white rounded-2xl border border-slate-200 p-5">
        <div className="font-semibold mb-4">Notifications</div>
        <div className="space-y-4">
          {[
            { label: "Remind me before tasks start",        sub: "Get a notification 5 minutes before planned start time", value: notifyBefore,  set: setNotifyBefore  },
            { label: "Celebrate task completions",          sub: "Show a notification when you mark a task as success",    value: notifySuccess, set: setNotifySuccess },
            { label: "Weekly performance summary",          sub: "Email digest every Sunday with your week's analytics",  value: notifyWeekly,  set: setNotifyWeekly  },
            { label: "AI coaching tips",                    sub: "Personalized suggestions based on your patterns",       value: notifyAI,      set: setNotifyAI      },
            { label: "Group task updates",                  sub: "Notify when teammates complete shared tasks",           value: notifyGroup,   set: setNotifyGroup   },
          ].map(({ label, sub, value, set }) => (
            <div key={label} className="flex items-start justify-between gap-4">
              <div>
                <div className="text-sm font-medium">{label}</div>
                <div className="text-xs text-slate-500 mt-0.5">{sub}</div>
              </div>
              <Toggle checked={value} onChange={set} />
            </div>
          ))}
        </div>
      </section>

      {/* ── Data & Privacy ───────────────────────────────────────────────── */}
      <section className="bg-white rounded-2xl border border-slate-200 p-5">
        <div className="font-semibold mb-4">Data &amp; Privacy</div>
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-sm font-medium">Export my data</div>
              <div className="text-xs text-slate-500">Download all your tasks and analytics as JSON</div>
            </div>
            <button
              onClick={handleExport}
              className="px-3 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm transition-colors"
            >
              Export
            </button>
          </div>
          <div className="border-t border-slate-100 pt-3 flex items-center justify-between">
            <div>
              <div className="text-sm font-medium">Sign out</div>
              <div className="text-xs text-slate-500">Sign out from this device</div>
            </div>
            <button
              onClick={handleLogout}
              className="px-3 py-2 rounded-xl bg-slate-100 hover:bg-rose-50 hover:text-rose-600 text-sm transition-colors"
            >
              Sign out
            </button>
          </div>
        </div>
      </section>

      {/* ── Danger Zone ──────────────────────────────────────────────────── */}
      <section className="bg-white rounded-2xl border border-rose-200 p-5">
        <div className="font-semibold text-rose-700 mb-1">Danger zone</div>
        <div className="text-sm text-slate-500 mb-4">
          These actions are permanent and cannot be undone.
        </div>

        {!showDeleteConfirm ? (
          <button
            onClick={() => setShowDeleteConfirm(true)}
            className="px-4 py-2 rounded-xl bg-rose-50 text-rose-700 border border-rose-200 text-sm font-semibold hover:bg-rose-100 transition-colors"
          >
            Delete account
          </button>
        ) : (
          <div className="space-y-3">
            <div className="text-sm text-rose-700 font-medium">
              Type <span className="font-mono bg-rose-50 px-1 rounded">DELETE</span> to confirm account deletion.
            </div>
            <input
              className="w-full bg-slate-100 rounded-xl px-4 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-rose-200"
              placeholder="Type DELETE to confirm"
              value={deleteInput}
              onChange={(e) => setDeleteInput(e.target.value)}
            />
            <div className="flex gap-2">
              <button
                onClick={() => { setShowDeleteConfirm(false); setDeleteInput(""); }}
                className="px-4 py-2 rounded-xl bg-slate-100 text-sm font-medium hover:bg-slate-200 transition-colors"
              >
                Cancel
              </button>
              <button
                disabled={deleteInput !== "DELETE"}
                className="px-4 py-2 rounded-xl bg-rose-500 text-white text-sm font-semibold hover:bg-rose-600 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                onClick={() => toast.info("Account deletion requires backend integration.")}
              >
                Delete my account
              </button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
