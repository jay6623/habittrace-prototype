"use client";

import { useEffect, useId, useRef } from "react";

export default function Dialog({
  title,
  children,
  onClose,
  busy = false,
  variant = "default",
}: {
  title: string;
  children: React.ReactNode;
  onClose: () => void;
  busy?: boolean;
  variant?: "default" | "coach";
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  useEffect(() => {
    const dialog = ref.current;
    const previous = document.activeElement as HTMLElement | null;
    dialog?.showModal();
    return () => {
      dialog?.close();
      previous?.focus();
    };
  }, []);
  useEffect(() => {
    if (variant !== "coach") return;
    const viewport = window.visualViewport;
    const updateViewport = () => {
      const dialog = ref.current;
      if (!dialog) return;
      const style = dialog.style;
      style.setProperty("--coach-viewport-height", `${viewport?.height ?? window.innerHeight}px`);
      style.setProperty("--coach-viewport-width", `${viewport?.width ?? window.innerWidth}px`);
      style.setProperty("--coach-viewport-top", `${viewport?.offsetTop ?? 0}px`);
      style.setProperty("--coach-viewport-left", `${viewport?.offsetLeft ?? 0}px`);
      dialog.dataset.compactHeight = String((viewport?.height ?? window.innerHeight) < 480);
      dialog.dataset.tightHeight = String((viewport?.height ?? window.innerHeight) < 340);
    };
    updateViewport();
    viewport?.addEventListener("resize", updateViewport);
    viewport?.addEventListener("scroll", updateViewport);
    window.addEventListener("resize", updateViewport);
    return () => {
      viewport?.removeEventListener("resize", updateViewport);
      viewport?.removeEventListener("scroll", updateViewport);
      window.removeEventListener("resize", updateViewport);
    };
  }, [variant]);
  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onCancel={(event) => {
        event.preventDefault();
        if (!busy) onClose();
      }}
      className={variant === "coach"
        ? "group/coach fixed inset-auto left-[calc(var(--coach-viewport-left,0px)+var(--coach-viewport-width,100vw)/2)] top-[calc(var(--coach-viewport-top,0px)+var(--coach-viewport-height,100dvh)/2)] m-0 h-[min(88dvh,880px,calc(var(--coach-viewport-height,100dvh)-1rem))] w-[min(460px,calc(var(--coach-viewport-width,100vw)-1rem))] max-h-none max-w-none -translate-x-1/2 -translate-y-1/2 flex-col overflow-hidden rounded-3xl border border-slate-200 bg-white p-3 text-slate-950 shadow-xl backdrop:bg-slate-950/40 open:flex sm:p-4"
        : "m-auto max-h-[90dvh] w-[calc(100%-2rem)] max-w-lg rounded-3xl border border-slate-200 bg-white p-6 text-slate-950 shadow-xl backdrop:bg-slate-950/40"}
    >
      <div className={`${variant === "coach" ? "mb-3 shrink-0" : "mb-5"} flex items-center justify-between gap-4`}>
        <h2 id={titleId} className="min-w-0 break-words text-xl font-bold">
          {title}
        </h2>
        <button
          type="button"
          aria-label="Close dialog"
          disabled={busy}
          onClick={onClose}
          className="btn-secondary"
        >
          ×
        </button>
      </div>
      {children}
    </dialog>
  );
}
