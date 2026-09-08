"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";
import { getTasks, type Task } from "@/lib/api";

// Map pathname → page title
function getPageTitle(pathname: string): { sub: string; title: string } {
  if (pathname === "/dashboard")              return { sub: "Home", title: "Execution Dashboard" };
  if (pathname === "/dashboard/habits")       return { sub: "Habit Tracking", title: "Today's Tasks" };
  if (pathname === "/dashboard/analytics")    return { sub: "Analytics", title: "Performance Insights" };
  if (pathname === "/dashboard/calendar")     return { sub: "Calendar", title: "Task Calendar" };
  if (pathname === "/dashboard/scheduler")    return { sub: "Scheduler", title: "Schedule Planner" };
  if (pathname === "/dashboard/settings")     return { sub: "Settings", title: "Account Settings" };
  return { sub: "HabitTrace", title: "Dashboard" };
}

function formatResultDate(iso: string): string {
  const d = new Date(`${iso}T12:00:00`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}

const STATUS_STYLES: Record<Task["task_status"], string> = {
  success: "bg-emerald-100 text-emerald-700",
  failed: "bg-rose-100 text-rose-700",
  pending: "bg-slate-100 text-slate-500",
};

export default function TopBar() {
  const { user, displayName } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const { sub, title } = getPageTitle(pathname);

  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);
  const [results, setResults] = useState<Task[]>([]);

  const allTasksRef = useRef<Task[] | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  async function ensureTasksLoaded(): Promise<Task[]> {
    if (allTasksRef.current) return allTasksRef.current;
    setSearching(true);
    setSearchError(null);
    try {
      const tasks = await getTasks();
      allTasksRef.current = tasks;
      return tasks;
    } catch {
      setSearchError("Couldn't load tasks to search.");
      return [];
    } finally {
      setSearching(false);
    }
  }

  // Debounced search as the user types.
  useEffect(() => {
    const q = query.trim().toLowerCase();
    if (!q) {
      setResults([]);
      setSearchError(null);
      return;
    }

    let cancelled = false;
    const timer = setTimeout(() => {
      ensureTasksLoaded().then((all) => {
        if (cancelled) return;
        const matches = all.filter(
          (t) =>
            t.title.toLowerCase().includes(q) ||
            t.task_category.toLowerCase().includes(q),
        );
        setResults(matches.slice(0, 8));
      });
    }, 200);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query]);

  // Close the dropdown on outside click or Escape.
  useEffect(() => {
    function handlePointerDown(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, []);

  function goToResult(task: Task) {
    setQuery("");
    setResults([]);
    setOpen(false);
    router.push(`/dashboard/habits?date=${task.planned_date}`);
  }

  async function handleLogout() {
    try {
      await supabase.auth.signOut();
    } catch {
      // ignore
    }
    router.push("/login");
  }

  return (
    <header className="bg-white border-b border-slate-200 sticky top-0 z-20">
      <div className="px-5 py-3 flex items-center justify-between gap-3">
        {/* Left: Page title */}
        <div>
          <div className="text-sm text-slate-500">{sub}</div>
          <div className="font-semibold">{title}</div>
        </div>

        {/* Right: Search + Avatar */}
        <div className="flex items-center gap-3">
          <div ref={containerRef} className="relative">
            <div className="flex items-center gap-2 bg-slate-100 rounded-xl px-3 py-2">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                <path
                  d="M21 21l-4.3-4.3m1.8-5.2a7 7 0 11-14 0 7 7 0 0114 0z"
                  stroke="currentColor" strokeWidth="2" strokeLinecap="round"
                />
              </svg>
              <input
                className="bg-transparent outline-none text-sm w-48"
                placeholder="Search tasks, habits…"
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setOpen(true);
                }}
                onFocus={() => {
                  if (query.trim()) setOpen(true);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && results[0]) goToResult(results[0]);
                }}
              />
            </div>

            {open && query.trim() && (
              <div className="absolute right-0 mt-2 w-80 max-h-80 overflow-y-auto rounded-2xl border border-slate-200 bg-white shadow-lg z-30 p-2">
                {searching ? (
                  <div className="px-3 py-6 text-center text-xs text-slate-400">Searching…</div>
                ) : searchError ? (
                  <div className="px-3 py-6 text-center text-xs text-rose-500">{searchError}</div>
                ) : results.length === 0 ? (
                  <div className="px-3 py-6 text-center text-xs text-slate-400">
                    No tasks match &quot;{query}&quot;.
                  </div>
                ) : (
                  results.map((task) => (
                    <button
                      key={task.id}
                      type="button"
                      onClick={() => goToResult(task)}
                      className="w-full flex items-center justify-between gap-2 rounded-xl px-3 py-2 text-left hover:bg-slate-50 transition-colors"
                    >
                      <span className="min-w-0">
                        <span className="block text-sm font-medium text-slate-900 truncate">
                          {task.title}
                        </span>
                        <span className="block text-xs text-slate-500">
                          {task.task_category} · {formatResultDate(task.planned_date)}
                        </span>
                      </span>
                      <span
                        className={`shrink-0 text-[10px] px-2 py-0.5 rounded-full font-medium ${STATUS_STYLES[task.task_status]}`}
                      >
                        {task.task_status}
                      </span>
                    </button>
                  ))
                )}
              </div>
            )}
          </div>

          {/* User + logout */}
          <div className="flex items-center gap-2 pl-2">
            <div className="h-9 w-9 rounded-full bg-slate-900 flex items-center justify-center text-white text-sm font-semibold">
              {displayName.charAt(0).toUpperCase()}
            </div>
            <div className="leading-tight">
              <div className="text-sm font-semibold">{displayName}</div>
              <div className="text-xs text-slate-500">
                {user?.email ?? "Demo mode"}
              </div>
            </div>
            {user && (
              <button
                onClick={handleLogout}
                className="ml-1 text-xs px-2 py-1 rounded-lg text-slate-500 hover:text-rose-600 hover:bg-rose-50 transition-colors"
                title="Sign out"
              >
                Sign out
              </button>
            )}
          </div>
        </div>
      </div>
    </header>
  );
}
