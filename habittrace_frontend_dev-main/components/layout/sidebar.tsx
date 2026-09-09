"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

export const navigation = [
  { href: "/dashboard", label: "Today", icon: "◉" },
  { href: "/dashboard/habits", label: "Plans", icon: "▦" },
  { href: "/dashboard/group", label: "Groups", icon: "◎" },
  { href: "/dashboard/analytics", label: "Insights", icon: "↗" },
  { href: "/dashboard/settings", label: "Settings", icon: "⚙" },
];
export function navActive(path: string, href: string) {
  if (href === "/dashboard")
    return path === href || path === "/dashboard/today";
  if (href.endsWith("habits")) return /habits|calendar|scheduler/.test(path);
  if (href.endsWith("settings"))
    return /settings|integrations|account/.test(path);
  return path === href;
}
export default function Sidebar() {
  const path = usePathname();
  return (
    <aside className="sticky top-0 hidden h-dvh w-56 shrink-0 flex-col border-r border-slate-200 bg-white p-4 lg:flex">
      <Link
        href="/dashboard"
        className="mb-8 flex items-center gap-3 px-2 py-3"
      >
        <span className="grid h-10 w-10 place-items-center rounded-xl bg-slate-950 font-bold text-white">
          HT
        </span>
        <span className="font-bold">HabitTrace</span>
      </Link>
      <nav aria-label="Main navigation" className="space-y-2">
        {navigation.map((item) => (
          <Link
            key={item.href}
            href={item.href}
            aria-current={navActive(path, item.href) ? "page" : undefined}
            className={`flex min-h-12 items-center gap-3 rounded-xl px-4 font-medium ${navActive(path, item.href) ? "bg-slate-950 text-white" : "text-slate-600 hover:bg-slate-100"}`}
          >
            <span aria-hidden="true">{item.icon}</span>
            {item.label}
          </Link>
        ))}
      </nav>
      <p className="mt-auto rounded-2xl bg-emerald-50 p-4 text-sm leading-relaxed text-emerald-900">
        Make room for what matters. A small, realistic plan is a good start.
      </p>
    </aside>
  );
}
