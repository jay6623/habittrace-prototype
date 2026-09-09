"use client";
import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import Sidebar from "@/components/layout/sidebar";
import TopBar from "@/components/layout/topbar";
import MobileNav from "@/components/mobile/mobile-nav";
import PlanTabs from "@/components/layout/plan-tabs";
import CoachChat from "@/components/coach-chat";
import Dialog from "@/components/ui/dialog";
import { useAuth } from "@/app/providers";
export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const [coach, setCoach] = useState(false);
  useEffect(() => {
    const openCoach = () => setCoach(true);
    window.addEventListener("habittrace:open-coach", openCoach);
    return () => window.removeEventListener("habittrace:open-coach", openCoach);
  }, []);
  useEffect(() => {
    if (!loading && !user)
      router.replace(`/login?next=${encodeURIComponent(pathname)}`);
  }, [user, loading, pathname, router]);
  if (loading)
    return (
      <div className="grid min-h-dvh place-items-center" role="status">
        Loading your workspace…
      </div>
    );
  if (!user) return null;
  return (
    <div className="flex min-h-dvh bg-slate-50">
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:fixed focus:z-50 focus:bg-white focus:p-4"
      >
        Skip to content
      </a>
      <Sidebar />
      <div className="min-w-0 flex-1">
        <TopBar />
        <main
          id="main-content"
          className="mx-auto max-w-7xl px-4 pb-32 pt-6 sm:px-6 lg:pb-24"
        >
          {/\/dashboard\/(habits|calendar|scheduler)$/.test(pathname) && (
            <PlanTabs />
          )}
          {children}
        </main>
      </div>
      <MobileNav />
      <button
        onClick={() => setCoach(true)}
        className="btn-primary fixed bottom-24 right-4 z-30 shadow-lg lg:bottom-6"
      >
        Ask coach
      </button>
      {coach && (
        <Dialog title="Plan with your coach" onClose={() => setCoach(false)}>
          <p className="mb-3 text-sm text-slate-500">
            Ask about your schedule or make a plan. Review proposed changes
            before applying them.
          </p>
          <div className="h-[60dvh]">
            <CoachChat />
          </div>
        </Dialog>
      )}
    </div>
  );
}
