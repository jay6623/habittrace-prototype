"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const items = [
  {
    href: "/dashboard/today",
    label: "Today",
    icon: (
      <path
        d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-5v-6h-4v6H5a1 1 0 0 1-1-1v-9.5Z"
        stroke="currentColor"
        strokeLinejoin="round"
        strokeWidth="2"
      />
    ),
  },
  {
    href: "/dashboard/today/calendar",
    label: "Calendar",
    icon: (
      <>
        <rect height="17" rx="2" stroke="currentColor" strokeWidth="2" width="18" x="3" y="4" />
        <path d="M8 2v4M16 2v4M3 9h18" stroke="currentColor" strokeLinecap="round" strokeWidth="2" />
      </>
    ),
  },
] as const;

export default function MobileNav() {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Mobile navigation"
      className="fixed inset-x-0 bottom-0 z-40 mx-auto grid w-full max-w-lg grid-cols-2 border-t border-slate-200 bg-white/95 px-5 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 shadow-[0_-8px_30px_rgba(15,23,42,0.08)] backdrop-blur"
    >
      {items.map((item) => {
        const active =
          item.href === "/dashboard/today"
            ? pathname === item.href
            : pathname.startsWith(item.href);
        return (
          <Link
            aria-current={active ? "page" : undefined}
            className={`flex min-h-14 flex-col items-center justify-center gap-1 rounded-2xl text-xs font-bold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-900 ${
              active ? "text-slate-950" : "text-slate-400 hover:text-slate-700"
            }`}
            href={item.href}
            key={item.href}
          >
            <svg aria-hidden="true" fill="none" height="22" viewBox="0 0 24 24" width="22">
              {item.icon}
            </svg>
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
