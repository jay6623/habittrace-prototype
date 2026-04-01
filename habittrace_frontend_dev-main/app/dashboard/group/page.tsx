"use client";

import { useState } from "react";

// ── Types ─────────────────────────────────────────────────────────────────
interface Member {
  id: string;
  name: string;
  avatar: string;
  role: "admin" | "member";
  tasksToday: number;
  successRate: number;
  online: boolean;
}

interface GroupTask {
  id: string;
  title: string;
  assignee: string;
  category: string;
  dueTime: string;
  status: "pending" | "success" | "failed";
  priority: "high" | "medium" | "low";
}

// ── Static demo data (replace with API when group backend is ready) ──────
const demoMembers: Member[] = [
  { id: "1", name: "You",         avatar: "Y", role: "admin",  tasksToday: 4, successRate: 75, online: true  },
  { id: "2", name: "Alex Kim",    avatar: "A", role: "member", tasksToday: 3, successRate: 67, online: true  },
  { id: "3", name: "Sarah Park",  avatar: "S", role: "member", tasksToday: 5, successRate: 80, online: false },
  { id: "4", name: "James Lee",   avatar: "J", role: "member", tasksToday: 2, successRate: 50, online: false },
];

const demoTasks: GroupTask[] = [
  { id: "1", title: "Prepare presentation slides", assignee: "You",        category: "Work",   dueTime: "2:00 PM", status: "pending", priority: "high"   },
  { id: "2", title: "Review project proposal",     assignee: "Alex Kim",   category: "Work",   dueTime: "3:00 PM", status: "success", priority: "high"   },
  { id: "3", title: "Team standup notes",          assignee: "Sarah Park", category: "Work",   dueTime: "10 AM",   status: "success", priority: "medium" },
  { id: "4", title: "Update task tracker",         assignee: "James Lee",  category: "Chores", dueTime: "5:00 PM", status: "pending", priority: "low"    },
  { id: "5", title: "Send weekly report",          assignee: "You",        category: "Work",   dueTime: "6:00 PM", status: "pending", priority: "high"   },
];

const priorityBadge: Record<string, string> = {
  high:   "bg-rose-100 text-rose-700",
  medium: "bg-amber-100 text-amber-700",
  low:    "bg-slate-100 text-slate-600",
};

const categoryChip: Record<string, string> = {
  Work:    "bg-violet-100 text-violet-800",
  Study:   "bg-sky-100 text-sky-800",
  Chores:  "bg-amber-100 text-amber-800",
  Other:   "bg-slate-100 text-slate-600",
};

// ── Component ─────────────────────────────────────────────────────────────
export default function GroupPage() {
  const [tab, setTab] = useState<"tasks" | "members" | "overview">("tasks");
  const [showInvite, setShowInvite] = useState(false);
  const [inviteCode] = useState("HT-" + Math.random().toString(36).slice(2, 8).toUpperCase());

  const pending = demoTasks.filter((t) => t.status === "pending").length;
  const done    = demoTasks.filter((t) => t.status === "success").length;
  const groupRate = Math.round((done / demoTasks.length) * 100);

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <div className="text-sm text-slate-500">Group Scheduling</div>
            <span className="text-xs px-2 py-0.5 rounded-full bg-violet-100 text-violet-700 font-medium">Beta</span>
          </div>
          <h1 className="text-2xl font-bold">Study &amp; Work Group</h1>
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setShowInvite(!showInvite)}
            className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm font-medium transition-colors"
          >
            Invite member
          </button>
          <button className="px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors">
            + Add group task
          </button>
        </div>
      </div>

      {/* Invite modal */}
      {showInvite && (
        <div className="bg-white rounded-2xl border border-violet-200 p-5">
          <div className="font-semibold mb-1">Invite to group</div>
          <div className="text-sm text-slate-500 mb-3">
            Share this code with teammates — they can join from their HabitTrace account.
          </div>
          <div className="flex gap-2">
            <div className="flex-1 bg-slate-100 rounded-xl px-4 py-3 font-mono text-sm tracking-wider text-slate-700">
              {inviteCode}
            </div>
            <button
              onClick={() => navigator.clipboard?.writeText(inviteCode)}
              className="px-4 py-3 rounded-xl bg-slate-900 text-white text-sm hover:bg-slate-800 transition-colors"
            >
              Copy
            </button>
          </div>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Group success rate</div>
          <div className="text-2xl font-bold mt-1 text-emerald-600">{groupRate}%</div>
          <div className="mt-2 h-2 rounded-full bg-slate-100 overflow-hidden">
            <div className="h-full bg-emerald-400 rounded-full" style={{ width: `${groupRate}%` }} />
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Group tasks today</div>
          <div className="flex items-baseline gap-1 mt-1">
            <span className="text-2xl font-bold text-emerald-600">{done}</span>
            <span className="text-sm text-slate-500">/ {demoTasks.length}</span>
          </div>
          <div className="text-xs text-slate-500 mt-1">{pending} remaining</div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Members</div>
          <div className="text-2xl font-bold mt-1">{demoMembers.length}</div>
          <div className="text-xs text-slate-500 mt-1">
            {demoMembers.filter((m) => m.online).length} online now
          </div>
        </div>
        <div className="bg-white rounded-2xl border border-slate-200 p-4">
          <div className="text-xs text-slate-500">Top performer</div>
          <div className="text-lg font-bold mt-1 truncate">
            {[...demoMembers].sort((a, b) => b.successRate - a.successRate)[0].name}
          </div>
          <div className="text-xs text-emerald-600 mt-1">
            {Math.max(...demoMembers.map((m) => m.successRate))}% success rate
          </div>
        </div>
      </div>

      {/* Tab navigation */}
      <div className="flex rounded-xl border border-slate-200 overflow-hidden w-fit">
        {(["tasks", "members", "overview"] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm font-medium capitalize transition-colors border-r border-slate-200 last:border-r-0 ${
              tab === t ? "bg-slate-900 text-white" : "bg-white text-slate-500 hover:text-slate-700"
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {/* Tasks tab */}
      {tab === "tasks" && (
        <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
          <div className="p-5 border-b border-slate-200">
            <div className="font-semibold">Group tasks</div>
            <div className="text-sm text-slate-500">Shared tasks assigned to team members</div>
          </div>
          <div className="divide-y divide-slate-100">
            {demoTasks.map((task) => (
              <div key={task.id} className={`px-5 py-4 ${
                task.status === "success" ? "bg-emerald-50/40" :
                task.status === "failed"  ? "bg-rose-50/40" : ""
              }`}>
                <div className="flex items-start gap-3">
                  <div className={`mt-1 h-3 w-3 rounded-full shrink-0 ${
                    task.status === "success" ? "bg-emerald-400" :
                    task.status === "failed"  ? "bg-rose-400" : "bg-slate-300"
                  }`} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className={`text-sm font-medium ${task.status !== "pending" ? "text-slate-400 line-through" : ""}`}>
                        {task.title}
                      </span>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${categoryChip[task.category] ?? "bg-slate-100 text-slate-600"}`}>
                        {task.category}
                      </span>
                      <span className={`text-xs px-2 py-0.5 rounded-full ${priorityBadge[task.priority]}`}>
                        {task.priority}
                      </span>
                    </div>
                    <div className="text-xs text-slate-500 mt-1">
                      Assigned to <span className="font-medium">{task.assignee}</span> · Due {task.dueTime}
                    </div>
                  </div>
                  <div className="text-xs text-slate-400 shrink-0">
                    {task.status === "success" ? "✓ Done" : task.status === "failed" ? "✗ Failed" : "Pending"}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Members tab */}
      {tab === "members" && (
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          {demoMembers.map((member) => (
            <div key={member.id} className="bg-white rounded-2xl border border-slate-200 p-5">
              <div className="flex items-center gap-3 mb-3">
                <div className="relative">
                  <div className="h-11 w-11 rounded-full bg-slate-900 text-white grid place-items-center font-bold text-sm">
                    {member.avatar}
                  </div>
                  {member.online && (
                    <div className="absolute bottom-0 right-0 h-3 w-3 rounded-full bg-emerald-400 border-2 border-white" />
                  )}
                </div>
                <div>
                  <div className="font-semibold text-sm">{member.name}</div>
                  <div className="text-xs text-slate-500 capitalize">{member.role}</div>
                </div>
              </div>
              <div className="space-y-2">
                <div className="flex justify-between text-xs">
                  <span className="text-slate-500">Tasks today</span>
                  <span className="font-medium">{member.tasksToday}</span>
                </div>
                <div className="flex justify-between text-xs">
                  <span className="text-slate-500">Success rate</span>
                  <span className={`font-medium ${member.successRate >= 70 ? "text-emerald-600" : member.successRate >= 50 ? "text-amber-500" : "text-rose-500"}`}>
                    {member.successRate}%
                  </span>
                </div>
                <div className="h-1.5 rounded-full bg-slate-100 overflow-hidden mt-1">
                  <div
                    className={`h-full rounded-full ${member.successRate >= 70 ? "bg-emerald-400" : member.successRate >= 50 ? "bg-amber-400" : "bg-rose-400"}`}
                    style={{ width: `${member.successRate}%` }}
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Overview tab */}
      {tab === "overview" && (
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-5">
          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-4">Task completion by member</div>
            <div className="space-y-4">
              {demoMembers.map((m) => (
                <div key={m.id}>
                  <div className="flex justify-between text-sm mb-1">
                    <span>{m.name}</span>
                    <span className="text-slate-500">{m.successRate}%</span>
                  </div>
                  <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                    <div
                      className={`h-full rounded-full ${m.successRate >= 70 ? "bg-emerald-400" : m.successRate >= 50 ? "bg-amber-400" : "bg-rose-400"}`}
                      style={{ width: `${m.successRate}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-white rounded-2xl border border-slate-200 p-5">
            <div className="font-semibold mb-4">Group activity feed</div>
            <div className="space-y-3">
              {[
                { who: "Alex Kim",   action: "completed",  task: "Review project proposal", time: "2m ago",  color: "bg-emerald-400" },
                { who: "Sarah Park", action: "completed",  task: "Team standup notes",       time: "15m ago", color: "bg-emerald-400" },
                { who: "You",        action: "added",      task: "Send weekly report",       time: "1h ago",  color: "bg-sky-400"     },
                { who: "James Lee",  action: "started",    task: "Update task tracker",      time: "2h ago",  color: "bg-amber-400"   },
              ].map((item, i) => (
                <div key={i} className="flex items-start gap-3">
                  <div className={`mt-1.5 h-2 w-2 rounded-full shrink-0 ${item.color}`} />
                  <div className="text-sm">
                    <span className="font-medium">{item.who}</span>
                    {" "}{item.action}{" "}
                    <span className="text-slate-600">&quot;{item.task}&quot;</span>
                    <span className="text-xs text-slate-400 ml-2">{item.time}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      <div className="text-xs text-slate-400 text-center py-2">
        Group scheduling is in Beta — real-time sync and more features coming soon.
      </div>
    </div>
  );
}
