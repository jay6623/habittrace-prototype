"use client";

import Link from "next/link";
import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";

export default function MobileAccount() {
  const { user, displayName } = useAuth();
  const router = useRouter();
  const [name, setName] = useState(displayName);
  const [saving, setSaving] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [message, setMessage] = useState<{ text: string; tone: "success" | "error" } | null>(null);

  useEffect(() => {
    setName(displayName);
  }, [displayName]);

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const nextName = name.trim();
    if (!nextName) {
      setMessage({ text: "Enter a display name.", tone: "error" });
      return;
    }

    setSaving(true);
    setMessage(null);
    try {
      const { error } = await supabase.auth.updateUser({
        data: { first_name: nextName },
      });
      if (error) throw error;
      setName(nextName);
      setMessage({ text: "Profile updated.", tone: "success" });
    } catch (caught) {
      setMessage({
        text: caught instanceof Error ? caught.message : "We couldn't update your profile.",
        tone: "error",
      });
    } finally {
      setSaving(false);
    }
  }

  async function handleSignOut() {
    if (signingOut) return;
    setSigningOut(true);
    setMessage(null);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      router.replace("/login?next=/dashboard/today");
    } catch (caught) {
      setMessage({
        text: caught instanceof Error ? caught.message : "We couldn't sign you out. Try again.",
        tone: "error",
      });
      setSigningOut(false);
    }
  }

  const initial = (name || user?.email || "H").charAt(0).toUpperCase();

  return (
    <main
      className="mx-auto min-h-dvh w-full max-w-lg overflow-x-hidden bg-slate-50 px-4 pb-[calc(6rem+env(safe-area-inset-bottom))] pt-[max(1rem,env(safe-area-inset-top))] text-slate-950"
      lang="en"
    >
      <header className="flex items-center gap-3 py-3">
        <Link
          aria-label="Back to Today"
          className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-white text-xl text-slate-700 shadow-sm ring-1 ring-slate-200 hover:bg-slate-100"
          href="/dashboard/today"
        >
          ←
        </Link>
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-slate-400">HabitTrace</p>
          <h1 className="text-2xl font-bold tracking-tight">Account</h1>
        </div>
      </header>

      <section className="mt-4 rounded-3xl bg-slate-950 p-5 text-white shadow-xl shadow-slate-300">
        <div className="flex items-center gap-4">
          <div className="grid h-16 w-16 shrink-0 place-items-center rounded-2xl bg-white text-2xl font-bold text-slate-950">
            {initial}
          </div>
          <div className="min-w-0">
            <h2 className="truncate text-xl font-bold">{displayName}</h2>
            <p className="mt-1 truncate text-sm text-slate-300">{user?.email}</p>
          </div>
        </div>
      </section>

      <form className="mt-5 rounded-3xl border border-slate-200 bg-white p-5" onSubmit={handleSave}>
        <h2 className="text-base font-bold">Profile</h2>
        <label className="mt-5 block text-sm font-semibold text-slate-700" htmlFor="mobile-display-name">
          Display name
        </label>
        <input
          autoComplete="name"
          className="mt-2 min-h-12 w-full rounded-2xl border border-slate-200 bg-slate-50 px-4 text-base outline-none focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100"
          id="mobile-display-name"
          maxLength={80}
          onChange={(event) => setName(event.target.value)}
          value={name}
        />

        <label className="mt-4 block text-sm font-semibold text-slate-700" htmlFor="mobile-account-email">
          Email
        </label>
        <input
          className="mt-2 min-h-12 w-full cursor-not-allowed rounded-2xl border border-slate-100 bg-slate-100 px-4 text-base text-slate-500"
          id="mobile-account-email"
          readOnly
          value={user?.email ?? ""}
        />

        {message && (
          <p
            className={`mt-4 rounded-2xl px-4 py-3 text-sm font-semibold ${
              message.tone === "success"
                ? "bg-emerald-50 text-emerald-800"
                : "bg-rose-50 text-rose-700"
            }`}
            role={message.tone === "error" ? "alert" : "status"}
          >
            {message.text}
          </p>
        )}

        <button
          className="mt-5 min-h-13 w-full rounded-2xl bg-slate-950 px-4 text-sm font-bold text-white hover:bg-slate-800 disabled:opacity-60"
          disabled={saving || signingOut || name.trim() === displayName}
          type="submit"
        >
          {saving ? "Saving…" : "Save profile"}
        </button>
      </form>

      <section className="mt-5 overflow-hidden rounded-3xl border border-slate-200 bg-white">
        <Link
          className="flex min-h-14 items-center justify-between border-b border-slate-100 px-5 text-sm font-bold text-slate-800 hover:bg-slate-50"
          href="/forgot-password"
        >
          Password & security
          <span aria-hidden="true" className="text-xl text-slate-400">›</span>
        </Link>
        <button
          className="min-h-14 w-full px-5 text-left text-sm font-bold text-rose-700 hover:bg-rose-50 disabled:opacity-50"
          disabled={saving || signingOut}
          onClick={() => void handleSignOut()}
          type="button"
        >
          {signingOut ? "Signing out…" : "Sign out"}
        </button>
      </section>

      <p className="mt-4 px-3 text-center text-xs leading-relaxed text-slate-400">
        Your plans are linked to this signed-in account, not to the display name.
      </p>
    </main>
  );
}
