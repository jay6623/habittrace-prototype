"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";

export default function ResetPasswordPage() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [checkingSession, setCheckingSession] = useState(true);
  const [hasSession, setHasSession] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setHasSession(Boolean(session));
      setCheckingSession(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (event === "PASSWORD_RECOVERY" || session) {
          setHasSession(Boolean(session));
          setCheckingSession(false);
        }
      },
    );

    return () => subscription.unsubscribe();
  }, []);

  async function handleUpdatePassword() {
    if (!password || !confirmPassword) {
      setError("Please enter and confirm your new password.");
      return;
    }
    if (password.length < 6) {
      setError("Password must be at least 6 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      setMessage("Password updated. You can now log in with your new password.");
      setTimeout(() => router.push("/login"), 1200);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Could not update password.";
      setError(msg);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="w-full max-w-lg rounded-3xl border border-slate-200 bg-white p-8 shadow-sm">
      <div className="mb-8 flex items-center gap-3">
        <div className="grid h-12 w-12 place-items-center rounded-2xl bg-slate-900 font-semibold text-white">
          HT
        </div>
        <div>
          <div className="text-lg font-semibold">Create new password</div>
          <div className="text-sm text-slate-500">Use a password reset link from your email</div>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-xl border border-rose-100 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {error}
        </div>
      )}

      {message && (
        <div className="mb-4 rounded-xl border border-emerald-100 bg-emerald-50 px-4 py-3 text-sm text-emerald-700">
          {message}
        </div>
      )}

      {!checkingSession && !hasSession && (
        <div className="mb-4 rounded-xl border border-amber-100 bg-amber-50 px-4 py-3 text-sm text-amber-700">
          This reset link is missing or expired. Request a new password reset email.
        </div>
      )}

      <div className="space-y-4">
        <div>
          <label className="mb-2 block text-sm font-medium">New password</label>
          <input
            className="w-full rounded-2xl border border-transparent bg-slate-100 px-4 py-3 text-sm outline-none focus:border-slate-200 focus:bg-white"
            type="password"
            placeholder="Enter new password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </div>

        <div>
          <label className="mb-2 block text-sm font-medium">Confirm password</label>
          <input
            className="w-full rounded-2xl border border-transparent bg-slate-100 px-4 py-3 text-sm outline-none focus:border-slate-200 focus:bg-white"
            type="password"
            placeholder="Confirm new password"
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
            onKeyDown={(event) => event.key === "Enter" && handleUpdatePassword()}
          />
        </div>

        <button
          onClick={handleUpdatePassword}
          disabled={loading || checkingSession || !hasSession}
          className="w-full rounded-2xl bg-slate-900 py-3 font-semibold text-white transition-colors hover:bg-slate-800 disabled:opacity-60"
        >
          {loading ? "Saving..." : "Update password"}
        </button>
      </div>

      <div className="mt-6 text-center text-sm text-slate-500">
        Need another link?{" "}
        <Link href="/forgot-password" className="font-medium text-slate-900 hover:underline">
          Send reset email
        </Link>
      </div>
    </div>
  );
}
