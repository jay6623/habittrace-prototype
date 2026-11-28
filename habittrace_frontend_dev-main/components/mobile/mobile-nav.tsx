"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { navigation, navActive } from "@/components/layout/sidebar";
import Dialog from "@/components/ui/dialog";
export default function MobileNav() {
  const path = usePathname();
  const navRef = useRef<HTMLElement>(null);
  useEffect(() => {
    const nav = navRef.current;
    if (!nav) return;
    const update = () => document.documentElement.style.setProperty("--mobile-nav-height", `${nav.getBoundingClientRect().height}px`);
    const observer = new ResizeObserver(update);
    observer.observe(nav);
    update();
    return () => { observer.disconnect(); document.documentElement.style.removeProperty("--mobile-nav-height"); };
  }, []);
  const [more, setMore] = useState(false);
  return <>
    <nav ref={navRef} aria-label="Mobile navigation" className="fixed inset-x-0 bottom-0 z-40 grid grid-cols-5 border-t border-slate-200 bg-white/95 pb-[max(.5rem,env(safe-area-inset-bottom))] pt-2 backdrop-blur lg:hidden">
      {navigation.slice(0, 4).map((item) => <Link key={item.href} href={item.href} aria-current={navActive(path, item.href) ? "page" : undefined}
        className={`flex min-h-12 min-w-0 flex-col items-center justify-center gap-1 text-xs font-semibold ${navActive(path, item.href) ? "text-slate-950" : "text-slate-500"}`}>
        <span className="text-lg" aria-hidden="true">{item.icon}</span>{item.label}</Link>)}
      <button type="button" onClick={() => setMore(true)} aria-expanded={more} aria-haspopup="dialog" className={`flex min-h-12 flex-col items-center justify-center gap-1 text-xs font-semibold ${navigation.slice(4).some((item) => navActive(path, item.href)) ? "text-slate-950" : "text-slate-500"}`}><span className="text-lg" aria-hidden="true">...</span>More</button>
    </nav>
    {more && <Dialog title="More" onClose={() => setMore(false)}><nav aria-label="More features" className="space-y-2">
      {navigation.slice(4).map((item) => <Link key={item.href} href={item.href} onClick={() => setMore(false)} aria-current={navActive(path, item.href) ? "page" : undefined} className="flex min-h-12 items-center gap-3 rounded-xl bg-slate-50 px-4 font-semibold"><span aria-hidden="true">{item.icon}</span>{item.label}</Link>)}
    </nav></Dialog>}
  </>;
}
