"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useToast, type AppNotification } from "@/components/ui/toast";

function formatWhen(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function tone(type: AppNotification["type"]): string {
  if (type === "error") return "bg-rose-500";
  if (type === "warn") return "bg-amber-500";
  if (type === "info") return "bg-sky-500";
  return "bg-emerald-500";
}

export default function NotificationMenu() {
  const { history, unreadCount, markNotificationsRead } = useToast();
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  function toggle() {
    setOpen((current) => {
      const next = !current;
      if (next) markNotificationsRead();
      return next;
    });
  }

  return (
    <div className="relative shrink-0" ref={rootRef}>
      <button
        aria-controls={panelId}
        aria-expanded={open}
        aria-label={
          unreadCount
            ? `Notifications, ${unreadCount} unread`
            : "Notifications"
        }
        className="relative grid h-11 w-11 place-items-center rounded-xl border border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
        onClick={toggle}
        type="button"
      >
        <svg aria-hidden="true" fill="none" height="18" viewBox="0 0 24 24" width="18">
          <path
            d="M6 9a6 6 0 1 1 12 0c0 7 3 7 3 7H3s3 0 3-7"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="1.8"
          />
          <path
            d="M10 18a2 2 0 0 0 4 0"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.8"
          />
        </svg>
        {unreadCount > 0 && (
          <span className="absolute -right-1 -top-1 grid h-5 min-w-5 place-items-center rounded-full bg-rose-600 px-1 text-[10px] font-bold text-white">
            {unreadCount > 9 ? "9+" : unreadCount}
          </span>
        )}
      </button>
      {open && (
        <div
          className="absolute right-0 z-30 mt-2 w-80 max-w-[calc(100vw-2rem)] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xl"
          id={panelId}
        >
          <div className="border-b border-slate-100 px-4 py-3 text-sm font-semibold">
            Notifications
          </div>
          {history.length === 0 ? (
            <p className="px-4 py-6 text-sm text-slate-500">
              No notifications yet. New alerts from plans, groups, and settings will show up here.
            </p>
          ) : (
            <ul className="max-h-96 overflow-y-auto">
              {history.map((item) => (
                <li key={item.id} className="border-b border-slate-100 px-4 py-3 last:border-b-0">
                  <div className="flex items-start gap-2">
                    <span className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${tone(item.type)}`} />
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-slate-900">{item.title}</p>
                      {item.message && (
                        <p className="mt-0.5 text-xs text-slate-500">{item.message}</p>
                      )}
                      <p className="mt-1 text-xs text-slate-400">{formatWhen(item.createdAt)}</p>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
