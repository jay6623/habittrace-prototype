"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import Sidebar from "@/components/layout/sidebar";
import TopBar from "@/components/layout/topbar";
import ScheduleChecker from "@/components/layout/schedule-checker";
import { useAuth } from "@/app/providers";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    // 로딩 끝났는데 로그인이 안 돼있으면 로그인 페이지로
    if (!loading && !user) {
      router.push("/login");
    }
  }, [user, loading, router]);

  // 로딩 중
  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50">
        <div className="text-sm text-slate-400">Loading…</div>
      </div>
    );
  }

  // 미로그인 (리다이렉트 중)
  if (!user) return null;

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
