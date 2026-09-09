"use client";

import {
  createContext,
  useCallback,
  useContext,
  useRef,
  useState,
  useEffect,
  useMemo,
} from "react";

type ToastType = "success" | "error" | "info" | "warn";

interface ToastItem {
  id: number;
  type: ToastType;
  title: string;
  message?: string;
  duration: number;
}

interface ToastContextType {
  success: (title: string, message?: string, duration?: number) => void;
  error: (title: string, message?: string, duration?: number) => void;
  info: (title: string, message?: string, duration?: number) => void;
  warn: (title: string, message?: string, duration?: number) => void;
}

const ToastContext = createContext<ToastContextType | null>(null);

const STYLES: Record<
  ToastType,
  {
    border: string;
    icon: string;
    iconBg: string;
    iconText: string;
    bar: string;
  }
> = {
  success: {
    border: "border-l-emerald-500",
    icon: "✓",
    iconBg: "bg-emerald-100",
    iconText: "text-emerald-700",
    bar: "bg-emerald-500",
  },
  error: {
    border: "border-l-rose-500",
    icon: "!",
    iconBg: "bg-rose-100",
    iconText: "text-rose-700",
    bar: "bg-rose-500",
  },
  info: {
    border: "border-l-sky-500",
    icon: "i",
    iconBg: "bg-sky-100",
    iconText: "text-sky-700",
    bar: "bg-sky-500",
  },
  warn: {
    border: "border-l-amber-500",
    icon: "!",
    iconBg: "bg-amber-100",
    iconText: "text-amber-700",
    bar: "bg-amber-500",
  },
};

const DEFAULT_DURATION = 4000;

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const idRef = useRef(0);
  const timers = useRef(new Set<ReturnType<typeof setTimeout>>());
  useEffect(() => {
    const active = timers.current;
    return () => {
      active.forEach(clearTimeout);
      active.clear();
    };
  }, []);

  const dismiss = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const push = useCallback(
    (
      type: ToastType,
      title: string,
      message?: string,
      duration: number = DEFAULT_DURATION,
    ) => {
      const id = ++idRef.current;
      setToasts((prev) => [...prev, { id, type, title, message, duration }]);
      if (duration > 0) {
        const timer = setTimeout(() => {
          dismiss(id);
          timers.current.delete(timer);
        }, duration);
        timers.current.add(timer);
      }
    },
    [dismiss],
  );

  const api = useMemo<ToastContextType>(
    () => ({
      success: (title, message, duration) =>
        push("success", title, message, duration),
      error: (title, message, duration) =>
        push("error", title, message, duration),
      info: (title, message, duration) =>
        push("info", title, message, duration),
      warn: (title, message, duration) =>
        push("warn", title, message, duration),
    }),
    [push],
  );

  return (
    <ToastContext.Provider value={api}>
      {children}

      <div
        className="pointer-events-none fixed top-4 right-4 z-[999] flex w-[calc(100%-2rem)] max-w-sm flex-col gap-2.5"
        aria-live="polite"
      >
        {toasts.map((t) => {
          const s = STYLES[t.type];
          return (
            <div
              key={t.id}
              role="status"
              className={`toast-enter pointer-events-auto relative flex items-start gap-3 overflow-hidden rounded-2xl border border-slate-200 bg-white p-3.5 pr-3 shadow-lg border-l-4 ${s.border}`}
            >
              <span
                className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs font-bold ${s.iconBg} ${s.iconText}`}
              >
                {s.icon}
              </span>
              <div className="min-w-0 flex-1">
                <div className="text-sm font-semibold text-slate-900">
                  {t.title}
                </div>
                {t.message && (
                  <div className="mt-0.5 text-xs text-slate-500">
                    {t.message}
                  </div>
                )}
              </div>
              <button
                type="button"
                onClick={() => dismiss(t.id)}
                aria-label="Dismiss notification"
                className="shrink-0 rounded-md p-1 text-slate-300 transition-colors hover:text-slate-500"
              >
                ✕
              </button>
              {t.duration > 0 && (
                <span
                  className={`absolute bottom-0 left-0 h-0.5 opacity-40 ${s.bar}`}
                  style={{
                    animation: `toast-progress ${t.duration}ms linear forwards`,
                  }}
                />
              )}
            </div>
          );
        })}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error("useToast must be used within a ToastProvider");
  }
  return ctx;
}
