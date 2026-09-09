"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

export default function PlanTabs() {
  const path = usePathname();
  return (
    <nav aria-label="Plan views" className="mb-6 flex flex-wrap gap-2">
      {[
        ["/dashboard/habits", "List"],
        ["/dashboard/calendar", "Calendar"],
        ["/dashboard/scheduler", "Find a time"],
      ].map(([href, label]) => (
        <Link
          key={href}
          href={href}
          aria-current={path === href ? "page" : undefined}
          className={path === href ? "btn-primary" : "btn-secondary"}
        >
          {label}
        </Link>
      ))}
    </nav>
  );
}
