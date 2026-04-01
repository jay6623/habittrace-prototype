"use client";

import { useState } from "react";

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
    description: "Sync tasks with your Google Calendar. Tasks appear as calendar events automatically.",
    category: "Calendar",
    connected: false,
    icon: "📅",
  },
  {
    id: "apple-calendar",
    name: "Apple Calendar",
    description: "Import events from Apple Calendar and track them as tasks in HabitTrace.",
    category: "Calendar",
    connected: false,
    icon: "🗓",
    comingSoon: true,
  },
  {
    id: "notion",
    name: "Notion",
    description: "Pull tasks from your Notion databases and sync completion status back.",
    category: "Productivity",
    connected: false,
    icon: "📝",
    comingSoon: true,
  },
  {
    id: "slack",
    name: "Slack",
    description: "Get reminders in Slack before tasks start and celebrate completions with your team.",
    category: "Communication",
    connected: false,
    icon: "💬",
    comingSoon: true,
  },
  {
    id: "todoist",
    name: "Todoist",
    description: "Two-way sync with Todoist — create tasks in either app and they stay in sync.",
    category: "Productivity",
    connected: false,
    icon: "✅",
    comingSoon: true,
  },
  {
    id: "github",
    name: "GitHub",
    description: "Create tasks from GitHub issues and link PRs to completed work sessions.",
    category: "Development",
    connected: false,
    icon: "🐙",
    comingSoon: true,
  },
  {
    id: "apple-health",
    name: "Apple Health",
    description: "Import sleep and activity data to improve HabitTrace's AI energy predictions.",
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

const CATEGORIES = ["All", "Calendar", "Productivity", "Communication", "Development", "Health", "Automation"];

// ── Component ──────────────────────────────────────────────────────────────
export default function IntegrationsPage() {
  const [integrations, setIntegrations] = useState(INTEGRATIONS);
  const [activeCategory, setActiveCategory] = useState("All");
  const [connecting, setConnecting] = useState<string | null>(null);

  const filtered =
    activeCategory === "All"
      ? integrations
      : integrations.filter((i) => i.category === activeCategory);

  const connectedCount = integrations.filter((i) => i.connected).length;

  async function handleConnect(id: string) {
    const intg = integrations.find((i) => i.id === id);
    if (!intg || intg.comingSoon) return;

    setConnecting(id);
    // Simulate OAuth flow delay
    await new Promise((r) => setTimeout(r, 1500));
    setIntegrations((prev) =>
      prev.map((i) => (i.id === id ? { ...i, connected: !i.connected } : i))
    );
    setConnecting(null);
  }

  return (
    <div className="space-y-5">
      {/* Header */}
      <div>
        <div className="text-sm text-slate-500">Integrations</div>
        <h1 className="text-2xl font-bold">Connected Apps</h1>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Connected</div>
          <div className="text-2xl font-bold mt-1 text-emerald-600">{connectedCount}</div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Available</div>
          <div className="text-2xl font-bold mt-1">{INTEGRATIONS.filter((i) => !i.comingSoon).length}</div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Coming soon</div>
          <div className="text-2xl font-bold mt-1">{INTEGRATIONS.filter((i) => i.comingSoon).length}</div>
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
                  <div className="text-xs text-slate-400 mt-0.5">{intg.category}</div>
                </div>
              </div>
            </div>

            <p className="text-sm text-slate-500 mt-3 leading-relaxed">
              {intg.description}
            </p>

            <button
              onClick={() => handleConnect(intg.id)}
              disabled={!!intg.comingSoon || connecting === intg.id}
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
                : intg.connected
                ? "Disconnect"
                : "Connect"}
            </button>
          </div>
        ))}
      </div>

      <div className="text-xs text-slate-400 text-center py-2">
        Suggest an integration →{" "}
        <a href="#" className="underline hover:text-slate-600">
          feedback@habittrace.app
        </a>
      </div>
    </div>
  );
}
