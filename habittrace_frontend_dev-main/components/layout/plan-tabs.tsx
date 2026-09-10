"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

export default function PlanTabs() {
  const path = usePathname();
  return (
    <nav
      aria-label="Plan views"
      className="mb-4 inline-flex flex-wrap gap-1 rounded-xl border border-emerald-100 bg-white p-1 shadow-sm"
    >
      {[
        ["/dashboard/habits", "List"],
        ["/dashboard/calendar", "Calendar"],
        ["/dashboard/scheduler", "Find a time"],
      ].map(([href, label]) => (
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
  );
}
