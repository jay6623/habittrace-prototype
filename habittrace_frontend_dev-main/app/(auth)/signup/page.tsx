"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { supabase } from "@/lib/supabase";
import { getOAuthRedirectBaseUrl } from "@/lib/site";

export default function SignupPage() {
  const router = useRouter();
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function handleSignup() {
    if (!firstName || !email || !password) {
      setError("Please fill in all required fields.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }
    if (!agreed) {
      setError("Please agree to the Terms of Service.");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: { first_name: firstName, last_name: lastName },
        },
      });

      if (authError) throw authError;

      // Supabase may require email confirmation
      setMessage(
        "Account created! Check your email to confirm, then log in."
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Signup failed.";
      if (msg.includes("fetch") || msg.includes("network") || msg.includes("URL")) {
        // Supabase not configured — demo mode
        console.warn("Supabase not configured — using demo mode");
        router.push("/onboarding/profile");
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogleSignup() {
    setLoading(true);
    setError(null);
    try {
      const { error: authError } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: `${getOAuthRedirectBaseUrl()}/onboarding/profile`,
          // Match the login page: always show Google's account chooser.
          queryParams: {
            prompt: "select_account",
          },
        },
      });
      if (authError) throw authError;
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Google signup failed.";
      if (msg.includes("fetch") || msg.includes("network") || msg.includes("URL")) {
        router.push("/onboarding/profile");
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  }

  if (message) {
    return (
      <div className="bg-white rounded-3xl border border-slate-200 shadow-sm p-8 max-w-lg w-full text-center">
        <div className="text-2xl font-bold mb-3">Check your inbox</div>
        <p className="text-slate-600 text-sm mb-6">{message}</p>
        <Link
          href="/login"
          className="inline-block px-6 py-3 rounded-2xl bg-slate-900 text-white font-semibold text-sm hover:bg-slate-800 transition-colors"
        >
          Go to Login
        </Link>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-3xl border border-slate-200 shadow-sm p-8 max-w-2xl w-full">
      <h2 className="text-2xl font-bold">Create your account</h2>
      <p className="mt-2 text-slate-600 text-sm">
        New users sign up here before moving to the productivity profile setup.
      </p>

      {error && (
        <div className="mt-4 px-4 py-3 rounded-xl bg-rose-50 border border-rose-100 text-sm text-rose-700">
          {error}
        </div>
      )}

      {/* Google Signup */}
      <button
        onClick={handleGoogleSignup}
        disabled={loading}
        className="mt-6 w-full flex items-center justify-center gap-3 bg-slate-900 text-white rounded-2xl py-3 font-semibold hover:bg-slate-800 transition-colors disabled:opacity-60"
      >
        <svg width="20" height="20" viewBox="0 0 24 24">
          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 01-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05" />
          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
        </svg>
        Sign up with Google
      </button>

      {/* Divider */}
      <div className="flex items-center gap-3 my-6">
        <div className="flex-1 h-px bg-slate-200" />
        <span className="text-xs text-slate-400">or use email</span>
        <div className="flex-1 h-px bg-slate-200" />
      </div>

      {/* Email Form */}
      <div className="grid md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-2">First name</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            placeholder="Paul"
            value={firstName}
            onChange={(e) => setFirstName(e.target.value)}
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Last name</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            placeholder="Cha"
            value={lastName}
            onChange={(e) => setLastName(e.target.value)}
          />
        </div>
        <div className="md:col-span-2">
          <label className="block text-sm font-medium mb-2">Email</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            placeholder="paul@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Password</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            type="password"
            placeholder="Create password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-2">Confirm password</label>
          <input
            className="w-full bg-slate-100 rounded-2xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            type="password"
            placeholder="Confirm password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
          />
        </div>
      </div>

      <div className="mt-5 flex items-start gap-2 text-sm text-slate-600">
        <input
          type="checkbox"
          className="mt-1"
          checked={agreed}
          onChange={(e) => setAgreed(e.target.checked)}
        />
        <span>I agree to the Terms of Service and Privacy Policy.</span>
      </div>

      <button
        onClick={handleSignup}
        disabled={loading}
        className="mt-6 w-full bg-slate-100 text-slate-900 rounded-2xl py-3 font-semibold hover:bg-slate-200 transition-colors disabled:opacity-60"
      >
        {loading ? "Creating account…" : "Create Account with Email"}
      </button>

      <div className="mt-6 text-sm text-slate-500 text-center">
        Already have an account?{" "}
        <Link href="/login" className="font-medium text-slate-900 hover:underline">
          Log in
        </Link>
      </div>
    </div>
  );
}
