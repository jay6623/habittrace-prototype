"use client";

import { useRouter, usePathname } from "next/navigation";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";

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

export default function TopBar() {
  const { user, displayName } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const { sub, title } = getPageTitle(pathname);

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
            />
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
