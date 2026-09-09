"use client";

import { useEffect } from "react";

export const DATA_CHANGED = "habittrace:data-changed";

export function notifyDataChanged() {
  if (typeof window !== "undefined")
    window.dispatchEvent(new Event(DATA_CHANGED));
}

/** Refresh after successful writes and when returning from another browser tab. */
export function useDataRefresh(refresh: () => unknown) {
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const schedule = () => {
      clearTimeout(timer);
      timer = setTimeout(refresh, 250);
    };
    const visible = () => {
      if (document.visibilityState === "visible") schedule();
    };
    window.addEventListener(DATA_CHANGED, schedule);
    window.addEventListener("focus", schedule);
    document.addEventListener("visibilitychange", visible);
    return () => {
      clearTimeout(timer);
      window.removeEventListener(DATA_CHANGED, schedule);
      window.removeEventListener("focus", schedule);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [refresh]);
}
