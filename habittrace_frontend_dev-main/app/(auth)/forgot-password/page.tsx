"use client";

import { useState } from "react";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { getOAuthRedirectBaseUrl } from "@/lib/site";

function getPasswordResetRedirectUrl(): string {
  const origin =
    typeof window !== "undefined" ? window.location.origin : getOAuthRedirectBaseUrl();
  return `${origin.replace(/\/+$/, "")}/reset-password`;
}

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSendResetEmail() {
    const trimmedEmail = email.trim();
    if (!trimmedEmail) {
      setError("Please enter your email address.");
      return;
    }

    setLoading(true);
    setError(null);
    setMessage(null);

    try {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(
        trimmedEmail,
        { redirectTo: getPasswordResetRedirectUrl() },
      );
      if (resetError) throw resetError;
      setMessage("Password reset email sent. Check your inbox and follow the link.");
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Could not send reset email.";
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
          <div className="text-lg font-semibold">Reset password</div>
          <div className="text-sm text-slate-500">Get a secure link by email</div>
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

      <div className="space-y-4">
        <div>
          <label className="mb-2 block text-sm font-medium">Email</label>
          <input
            className="w-full rounded-2xl border border-transparent bg-slate-100 px-4 py-3 text-sm outline-none focus:border-slate-200 focus:bg-white"
            type="email"
            placeholder="paul@example.com"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            onKeyDown={(event) => event.key === "Enter" && handleSendResetEmail()}
          />
        </div>

        <button
          onClick={handleSendResetEmail}
          disabled={loading}
          className="w-full rounded-2xl bg-slate-900 py-3 font-semibold text-white transition-colors hover:bg-slate-800 disabled:opacity-60"
        >
          {loading ? "Sending..." : "Send reset email"}
        </button>
      </div>

      <div className="mt-6 text-center text-sm text-slate-500">
        Remembered it?{" "}
        <Link href="/login" className="font-medium text-slate-900 hover:underline">
          Back to login
        </Link>
      </div>
    </div>
  );
}
