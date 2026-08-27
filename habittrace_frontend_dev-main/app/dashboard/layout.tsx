"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import Sidebar from "@/components/layout/sidebar";
import TopBar from "@/components/layout/topbar";
import ScheduleChecker from "@/components/layout/schedule-checker";
import MobileNav from "@/components/mobile/mobile-nav";
import { useAuth } from "@/app/providers";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const isMobileExperience = pathname.startsWith("/dashboard/today");

  useEffect(() => {
    // Redirect to sign-in once session loading is complete.
    if (!loading && !user) {
      const nextPath = pathname.startsWith("/dashboard") ? pathname : "/dashboard";
      router.replace(`/login?next=${encodeURIComponent(nextPath)}`);
    }
  }, [user, loading, pathname, router]);

  // Session loading state.
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50">
        <div className="text-sm text-slate-400">Loading…</div>
      </div>
    );
  }

  // Signed out while the redirect is in progress.
  if (!user) return null;

  if (isMobileExperience) {
    return (
      <div className="min-h-dvh bg-slate-100">
        {children}
        <MobileNav />
      </div>
    );
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <TopBar />
        <main className="flex-1 p-5">
          {children}
        </main>
      </div>
      <ScheduleChecker />
    </div>
  );
}
