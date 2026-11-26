"use client";

import { useSyncExternalStore, type ReactNode } from "react";

function subscribe(callback: () => void) {
  const media = window.matchMedia("(max-width: 1023px)");
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
}
const getSnapshot = () => window.matchMedia("(max-width: 1023px)").matches;

/** Secondary information is disclosed on phones; desktop content remains inline. */
export default function MobileDetails({ title, children }: { title: string; children: ReactNode }) {
  const mobile = useSyncExternalStore(subscribe, getSnapshot, () => false);
  if (!mobile) return <>{children}</>;
  return <details className="min-w-0 rounded-2xl border border-slate-200 bg-white p-3">
    <summary className="min-h-11 cursor-pointer content-center text-sm font-semibold text-slate-700">{title}</summary>
    <div className="mt-3 min-w-0">{children}</div>
  </details>;
}
