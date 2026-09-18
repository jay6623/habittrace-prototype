"use client";

import { useCallback, useEffect, useId, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "@/app/providers";
import { getTasks, type Task } from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";
import ProfileMenu from "@/components/profile/profile-menu";

export default function TopBar() {
  const router = useRouter();
  const path = usePathname();
  const { user } = useAuth();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Task[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [revision, setRevision] = useState(0);
  const listId = useId();
  const refresh = useCallback(() => setRevision((n) => n + 1), []);
  useDataRefresh(refresh);
  useEffect(() => {
    let cancelled = false;
    const q = query.trim().toLowerCase();
    setResults([]);
    setActive(0);
    setError(false);
    if (!q || !user) {
      setLoading(false);
      return;
    }
    setLoading(true);
    const timer = setTimeout(async () => {
      try {
        const all = await getTasks();
        if (!cancelled)
          setResults(
            all
              .filter((t) =>
                `${t.title} ${t.task_category}`.toLowerCase().includes(q),
              )
              .slice(0, 8),
          );
      } catch {
        if (!cancelled) setError(true);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query, revision, user]);
  function select(task: Task) {
    setOpen(false);
    setQuery("");
    router.push(
      `/dashboard/habits?date=${task.planned_date}&task=${encodeURIComponent(task.id)}`,
    );
  }
  const title = path.includes("group")
    ? "Groups"
    : path.includes("analytics")
      ? "Insights"
      : /settings|integrations/.test(path)
        ? "Settings"
        : /habits|calendar|scheduler/.test(path)
          ? "Plans"
          : "Today";
  return (
    <header className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 bg-white/95 px-4 py-3 backdrop-blur sm:px-6">
      <p className="font-semibold">{title}</p>
      <div className="flex min-w-0 flex-1 items-center justify-end gap-3 sm:max-w-md">
      <div
        className="relative min-w-0 flex-1"
        onBlur={(e) => {
          if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false);
        }}
      >
        <input
          aria-label="Search your plans"
          role="combobox"
          aria-controls={listId}
          aria-expanded={open && !!query.trim()}
          aria-autocomplete="list"
          aria-activedescendant={
            open && results[active] ? `${listId}-${active}` : undefined
          }
          className="field"
          placeholder="Search your plans…"
          value={query}
          onFocus={() => setOpen(true)}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onKeyDown={(e) => {
            if (e.key === "Escape") setOpen(false);
            if (e.key === "ArrowDown") {
              e.preventDefault();
              setOpen(true);
              setActive((n) => Math.min(n + 1, results.length - 1));
            }
            if (e.key === "ArrowUp") {
              e.preventDefault();
              setActive((n) => Math.max(n - 1, 0));
            }
            if (e.key === "Enter" && open && !loading && results[active]) {
              e.preventDefault();
              select(results[active]);
            }
          }}
        />
        {open && query.trim() && (
          <div className="absolute right-0 mt-2 w-full min-w-64 rounded-2xl border border-slate-200 bg-white p-2 shadow-xl">
            {loading ? (
              <p role="status" className="p-4 text-sm">
                Searching…
              </p>
            ) : error ? (
              <div role="alert" className="p-3 text-sm">
                Couldn’t load plans.{" "}
                <button className="btn-secondary" onClick={refresh}>
                  Retry
                </button>
              </div>
            ) : results.length === 0 ? (
              <p className="p-4 text-sm text-slate-500">No matching plans.</p>
            ) : null}
            <ul id={listId} role="listbox" aria-label="Matching plans">
              {results.map((task, i) => (
                <li
                  key={task.id}
                  id={`${listId}-${i}`}
                  role="option"
                  aria-selected={active === i}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => select(task)}
                  className={`cursor-pointer rounded-xl p-3 ${active === i ? "bg-slate-100" : "hover:bg-slate-50"}`}
                >
                  <p className="truncate text-sm font-semibold">{task.title}</p>
                  <p className="text-xs text-slate-500">
                    {task.planned_date} · {task.task_category} ·{" "}
                    {task.task_status === "success"
                      ? "Completed"
                      : task.task_status === "failed"
                        ? "Not completed"
                        : "Planned"}
                  </p>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
      <ProfileMenu menuPlacement="down" size="md" tone="light" />
      </div>
    </header>
  );
}
