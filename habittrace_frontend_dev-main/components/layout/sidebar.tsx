"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const mainLinks = [
  { href: "/dashboard",           label: "Home",             dot: "bg-emerald-400" },
  { href: "/dashboard/habits",    label: "Habit Tracking",   dot: "bg-sky-400" },
  { href: "/dashboard/analytics", label: "Analytics",        dot: "bg-violet-400" },
  { href: "/dashboard/scheduler", label: "Scheduler",        dot: "bg-amber-400" },
  { href: "/dashboard/calendar",  label: "Calendar",         dot: "bg-sky-400" },
  { href: "/dashboard/group",     label: "Group Scheduling", dot: "bg-rose-400", badge: "Beta" },
];

const toolLinks = [
  { href: "/dashboard/integrations", label: "Integrations", dot: "bg-slate-300" },
  { href: "/dashboard/settings",     label: "Settings",     dot: "bg-slate-300" },
];

export default function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="w-[260px] min-h-screen bg-white border-r border-slate-200 flex flex-col">
      {/* Logo */}
      <div className="p-5 flex items-center gap-3">
        <div className="h-10 w-10 rounded-xl bg-slate-900 text-white grid place-items-center font-semibold text-sm">
          HT
        </div>
        <div>
          <div className="font-semibold leading-tight">HabitTrace</div>
          <div className="text-xs text-slate-500">AI time + habit insights</div>
        </div>
      </div>

      {/* Main Nav */}
      <nav className="px-3 flex-1">
        <div className="text-xs font-semibold text-slate-400 px-3 mt-2 mb-2">MAIN</div>
        {mainLinks.map((link) => {
          const isActive = pathname === link.href;
          return (
            <Link
              key={link.href}
              href={link.href}
              className={`flex items-center justify-between gap-3 px-3 py-2 rounded-xl mt-1 transition-colors ${
                isActive
                  ? "bg-slate-900 text-white"
                  : "text-slate-700 hover:bg-slate-100"
              }`}
            >
              <span className="flex items-center gap-3">
                <span className={`inline-block h-2 w-2 rounded-full ${link.dot}`} />
                <span className="font-medium text-sm">{link.label}</span>
              </span>
              {link.badge && (
                <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">
                  {link.badge}
                </span>
              )}
            </Link>
          );
        })}

        <div className="text-xs font-semibold text-slate-400 px-3 mt-6 mb-2">TOOLS</div>
        {toolLinks.map((link) => {
          const isActive = pathname === link.href;
          return (
            <Link
              key={link.href}
              href={link.href}
              className={`flex items-center gap-3 px-3 py-2 rounded-xl mt-1 transition-colors ${
                isActive
                  ? "bg-slate-900 text-white"
                  : "text-slate-700 hover:bg-slate-100"
              }`}
            >
              <span className={`inline-block h-2 w-2 rounded-full ${link.dot}`} />
              <span className="font-medium text-sm">{link.label}</span>
            </Link>
          );
        })}
      </nav>

      {/* Focus Card */}
      <div className="mx-3 mb-5 p-4 rounded-2xl bg-slate-900 text-white">
        <div className="text-sm font-semibold">Today&apos;s focus</div>
        <div className="text-xs text-slate-300 mt-1">
          Keep tasks realistic. Avoid overbooking.
        </div>
        <button className="mt-3 w-full rounded-xl bg-white/10 hover:bg-white/15 px-3 py-2 text-sm">
          Review risks
        </button>
      </div>
    </aside>
  );
}