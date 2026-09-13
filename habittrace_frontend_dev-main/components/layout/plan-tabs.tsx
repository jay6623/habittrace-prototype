"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { getTasks } from "@/lib/api";
import { countUnloggedAttention } from "@/lib/unlogged";
import { useDataRefresh } from "@/lib/refresh";

const MAIN_TABS = [
  ["/dashboard/habits", "List"],
  ["/dashboard/calendar", "Calendar"],
  ["/dashboard/scheduler", "Find a time"],
] as const;

export default function PlanTabs() {
  const path = usePathname();
  const [unloggedCount, setUnloggedCount] = useState(0);

  const loadCount = useCallback(async () => {
    try {
      const tasks = await getTasks();
      setUnloggedCount(countUnloggedAttention(tasks));
    } catch {
      setUnloggedCount(0);
    }
  }, []);

  useEffect(() => {
    void loadCount();
  }, [loadCount]);
  useDataRefresh(loadCount);

  const unloggedActive = path === "/dashboard/habits/unlogged";

  return (
    <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
      <nav
        aria-label="Plan views"
        className="inline-flex flex-wrap gap-1 rounded-xl border border-emerald-100 bg-white p-1 shadow-sm"
      >
        {MAIN_TABS.map(([href, label]) => (
          <Link
            key={href}
            href={href}
            aria-current={path === href ? "page" : undefined}
            className={`inline-flex min-h-9 items-center justify-center rounded-lg px-3 py-2 text-sm font-semibold transition ${
              path === href
                ? "bg-emerald-600 text-white shadow-sm"
                : "text-slate-600 hover:bg-emerald-50 hover:text-emerald-800"
            }`}
          >
            {label}
          </Link>
        ))}
      </nav>
      <Link
        href="/dashboard/habits/unlogged"
        aria-current={unloggedActive ? "page" : undefined}
        className={`relative inline-flex min-h-9 items-center justify-center gap-2 rounded-xl border px-3 py-2 text-sm font-semibold shadow-sm transition ${
          unloggedActive
            ? "border-rose-600 bg-rose-600 text-white"
            : "border-slate-200 bg-white text-slate-700 hover:border-rose-200 hover:bg-rose-50 hover:text-rose-800"
        }`}
      >
        Unlogged
        {unloggedCount > 0 && (
          <span
            aria-label={`${unloggedCount} unlogged plans`}
            className="absolute -right-1.5 -top-1.5 grid h-5 min-w-5 place-items-center rounded-full bg-rose-600 px-1 text-[11px] font-bold text-white ring-2 ring-slate-50"
          >
            {unloggedCount > 99 ? "99+" : unloggedCount}
          </span>
        )}
      </Link>
    </div>
  );
}
