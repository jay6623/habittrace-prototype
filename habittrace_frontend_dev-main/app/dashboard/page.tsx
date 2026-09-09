"use client";

import { useEffect, useState } from "react";
import MobileToday from "@/components/mobile/mobile-today";
import DesktopCommandCenter from "@/components/layout/desktop-command-center";

export default function DashboardPage() {
  const [desktop, setDesktop] = useState<boolean | null>(null);

  useEffect(() => {
    const query = window.matchMedia("(min-width: 1024px)");
    const update = () => setDesktop(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  if (desktop === null) {
    return (
      <div className="space-y-5" aria-label="Loading your day" role="status">
        <div className="h-64 animate-pulse rounded-[2rem] bg-slate-200" />
        <div className="grid grid-cols-3 gap-5">
          <div className="col-span-2 h-80 animate-pulse rounded-3xl bg-slate-200" />
          <div className="h-80 animate-pulse rounded-3xl bg-slate-200" />
        </div>
      </div>
    );
  }

  return desktop ? <DesktopCommandCenter /> : <MobileToday />;
}
