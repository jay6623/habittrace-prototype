"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { getOAuthRedirectBaseUrl } from "@/lib/site";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleLogin() {
    if (!email || !password) {
      setError("Please enter your email and password.");
      return;
    }
    setLoading(true);
    setError(null);

    try {
      const { error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (authError) throw authError;
      router.push("/dashboard");
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Login failed.";
      // If Supabase is not configured, allow demo login
      if (msg.includes("fetch") || msg.includes("network") || msg.includes("URL")) {
        console.warn("Supabase not configured — using demo mode");
        router.push("/dashboard");
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogleLogin() {
    setLoading(true);
    setError(null);
    try {
      const { error: authError } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: `${getOAuthRedirectBaseUrl()}/dashboard`,
        },
      });
      if (authError) throw authError;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Google login failed.";
      if (msg.includes("fetch") || msg.includes("network") || msg.includes("URL")) {
        router.push("/dashboard");
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="bg-white rounded-3xl border border-slate-200 shadow-sm p-8 max-w-lg w-full">
      {/* Header */}
      <div className="flex items-center gap-3 mb-8">
        <div className="h-12 w-12 rounded-2xl bg-slate-900 text-white grid place-items-center font-semibold">
          HT
        </div>
        <div>
          <div className="font-semibold text-lg">Welcome back</div>
          <div className="text-sm text-slate-500">Log in to continue to HabitTrace</div>
        </div>
      </div>

      {error && (
        <div className="mb-4 px-4 py-3 rounded-xl bg-rose-50 border border-rose-100 text-sm text-rose-700">
          {error}
        </div>
      )}

      {/* Google Login */}
      <button
        onClick={handleGoogleLogin}
        disabled={loading}
        className="w-full flex items-center justify-center gap-3 bg-slate-900 text-white rounded-2xl py-3 font-semibold hover:bg-slate-800 transition-colors disabled:opacity-60"
      >
        <svg width="20" height="20" viewBox="0 0 24 24">
          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
        </svg>
        Continue with Google
      </button>

      {/* Divider */}
      <div className="flex items-center gap-3 my-6">
        <div className="flex-1 h-px bg-slate-200" />
        <span className="text-xs text-slate-400">or use email</span>
        <div className="flex-1 h-px bg-slate-200" />
      </div>

      {/* Email/Password */}
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium mb-2">Email</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            type="email"
            placeholder="paul@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleLogin()}
          />
        </div>
        <div>
          <div className="flex items-center justify-between mb-2">
            <label className="block text-sm font-medium">Password</label>
            <Link href="/forgot-password" className="text-sm text-slate-500 hover:underline">
              Forgot password?
            </Link>
          </div>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            type="password"
            placeholder="Enter your password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleLogin()}
          />
        </div>

        <button
          onClick={handleLogin}
          disabled={loading}
          className="w-full bg-slate-100 text-slate-900 rounded-2xl py-3 font-semibold hover:bg-slate-200 transition-colors disabled:opacity-60"
        >
          {loading ? "Signing in…" : "Log In with Email"}
        </button>
      </div>

      <div className="mt-6 text-sm text-slate-500 text-center">
        New to HabitTrace?{" "}
        <Link href="/signup" className="font-medium text-slate-900 hover:underline">
          Create an account
        </Link>
      </div>
    </div>
  );
}
