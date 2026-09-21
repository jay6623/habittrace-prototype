"use client";

import { FormEvent, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { supabase } from "@/lib/supabase";
import { getOAuthRedirectBaseUrl } from "@/lib/site";

/** Always land on Today after login (ignore any `?next=` bounce URL). */
function getPostLoginDestination(): string {
  if (typeof window === "undefined") return "/dashboard";
  const mobileOrInstalled =
    window.innerWidth < 768 || window.matchMedia("(display-mode: standalone)").matches;
  return mobileOrInstalled ? "/dashboard/today" : "/dashboard";
}

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
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
      router.replace(getPostLoginDestination());
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Login failed.");
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
          redirectTo: `${getOAuthRedirectBaseUrl()}${getPostLoginDestination()}`,
          // Signing out of HabitTrace does not end the Google browser session.
          // Ask Google for the account chooser so a different account can be picked.
          queryParams: {
            prompt: "select_account",
          },
        },
      });
      if (authError) throw authError;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Google login failed.");
      setLoading(false);
    }
  }

  return (
    <section className="w-full max-w-md rounded-3xl bg-white p-5 shadow-sm ring-1 ring-slate-200 sm:p-8">
      <header className="mb-7 text-center">
        <div className="mx-auto grid h-16 w-16 place-items-center rounded-2xl bg-slate-950 text-lg font-bold text-white shadow-lg shadow-slate-300">
          HT
        </div>
        <h1 className="mt-5 text-2xl font-bold tracking-tight text-slate-950">Welcome back</h1>
        <p className="mt-2 text-sm text-slate-500">Sign in to plan, start, and finish your day.</p>
      </header>

      {error && (
        <div className="mb-4 rounded-2xl border border-rose-100 bg-rose-50 px-4 py-3 text-sm font-medium text-rose-700" role="alert">
          {error}
        </div>
      )}

      <button
        className="flex min-h-14 w-full items-center justify-center gap-3 rounded-2xl bg-slate-950 px-4 font-bold text-white transition hover:bg-slate-800 disabled:opacity-60"
        disabled={loading}
        onClick={() => void handleGoogleLogin()}
        type="button"
      >
        <svg aria-hidden="true" height="20" viewBox="0 0 24 24" width="20">
          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
        </svg>
        Continue with Google
      </button>

      <div className="my-6 flex items-center gap-3" aria-hidden="true">
        <div className="h-px flex-1 bg-slate-200" />
        <span className="text-xs font-medium text-slate-400">OR USE EMAIL</span>
        <div className="h-px flex-1 bg-slate-200" />
      </div>

      <form className="space-y-4" onSubmit={handleLogin}>
        <div>
          <label className="mb-2 block text-sm font-semibold text-slate-700" htmlFor="login-email">Email</label>
          <input
            autoCapitalize="none"
            autoComplete="email"
            className="min-h-13 w-full rounded-2xl border border-transparent bg-slate-100 px-4 text-base outline-none focus:border-slate-400 focus:bg-white focus:ring-4 focus:ring-slate-100"
            id="login-email"
            inputMode="email"
            onChange={(event) => setEmail(event.target.value)}
            placeholder="you@example.com"
            required
            type="email"
            value={email}
          />
        </div>
        <div>
          <div className="mb-2 flex items-center justify-between gap-3">
            <label className="text-sm font-semibold text-slate-700" htmlFor="login-password">Password</label>
            <Link className="min-h-11 py-3 text-sm font-semibold text-slate-500 hover:text-slate-900" href="/forgot-password">
              Forgot password?
            </Link>
          </div>
          <input
            autoComplete="current-password"
            className="min-h-13 w-full rounded-2xl border border-transparent bg-slate-100 px-4 text-base outline-none focus:border-slate-400 focus:bg-white focus:ring-4 focus:ring-slate-100"
            id="login-password"
            onChange={(event) => setPassword(event.target.value)}
            placeholder="Enter your password"
            required
            type="password"
            value={password}
          />
        </div>

        <button
          className="min-h-14 w-full rounded-2xl bg-slate-100 px-4 font-bold text-slate-950 transition hover:bg-slate-200 disabled:opacity-60"
          disabled={loading}
          type="submit"
        >
          {loading ? "Signing in…" : "Sign in with email"}
        </button>
      </form>

      <p className="mt-6 text-center text-sm text-slate-500">
        New to HabitTrace?{" "}
        <Link className="font-bold text-slate-950 hover:underline" href="/signup">
          Create an account
        </Link>
      </p>
    </section>
  );
}
