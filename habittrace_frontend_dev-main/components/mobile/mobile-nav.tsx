"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { navigation, navActive } from "@/components/layout/sidebar";
export default function MobileNav() {
  const path = usePathname();
  return (
    <nav
      aria-label="Mobile navigation"
      className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-5 border-t border-slate-200 bg-white/95 pb-[max(.5rem,env(safe-area-inset-bottom))] pt-2 backdrop-blur lg:hidden"
    >
      {navigation.map((item) => (
        <Link
          key={item.href}
          href={item.href}
          aria-current={navActive(path, item.href) ? "page" : undefined}
          className={`flex min-h-12 flex-col items-center justify-center gap-1 text-xs font-semibold ${navActive(path, item.href) ? "text-slate-950" : "text-slate-500"}`}
        >
          <span className="text-lg" aria-hidden="true">
            {item.icon}
          </span>
          {item.label}
        </Link>
      ))}
    </nav>
  );
}
