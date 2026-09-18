"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/app/providers";
import { supabase } from "@/lib/supabase";
import { exportAccount } from "@/lib/api";
import {
  avatarInitials,
  clearUserAvatar,
  readAvatarUrl,
  uploadUserAvatar,
} from "@/lib/avatar";
import { readPreferences } from "@/lib/preferences";
import { useToast } from "@/components/ui/toast";
import Dialog from "@/components/ui/dialog";
import { syncProfileDisplayName } from "@/lib/profile";
import { notifyDataChanged } from "@/lib/refresh";

export default function SettingsPage() {
  const { user, displayName } = useAuth();
  if (!user) return null;
  return (
    <Settings
      key={user.id}
      user={user}
      displayName={displayName}
    />
  );
}

function Settings({
  user,
  displayName,
}: {
  user: NonNullable<ReturnType<typeof useAuth>["user"]>;
  displayName: string;
}) {
  const toast = useToast();
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const userId = user.id;
  const email = user.email ?? "";
  const metadata = user.user_metadata ?? {};
  const [name, setName] = useState(displayName);
  const [preferences, setPreferences] = useState(() =>
    readPreferences(metadata),
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [avatarMenuOpen, setAvatarMenuOpen] = useState(false);
  const [avatarBusy, setAvatarBusy] = useState(false);
  const [imageBroken, setImageBroken] = useState(false);
  const [confirmSignOut, setConfirmSignOut] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const avatarUrl = readAvatarUrl(user);
  const initials = avatarInitials(displayName, email);
  const showImage = Boolean(avatarUrl) && !imageBroken;
  const hasCustomAvatar =
    typeof metadata.avatar_url === "string" &&
    Boolean(metadata.avatar_url.trim());

  useEffect(() => {
    setPreferences(readPreferences(metadata));
    setImageBroken(false);
  }, [metadata]);
  useEffect(() => {
    setName(displayName);
  }, [displayName]);

  useEffect(() => {
    if (!avatarMenuOpen) return;
    function onPointer(event: MouseEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        setAvatarMenuOpen(false);
      }
    }
    document.addEventListener("mousedown", onPointer);
    return () => document.removeEventListener("mousedown", onPointer);
  }, [avatarMenuOpen]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (!name.trim()) {
      setError("Enter a display name.");
      return;
    }
    if (preferences.workEnd <= preferences.workStart) {
      setError("Daily availability must end after it starts.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const nextName = name.trim();
      const { error } = await supabase.auth.updateUser({
        data: { first_name: nextName, planning_preferences: preferences },
      });
      if (error) throw error;
      await syncProfileDisplayName(userId, nextName);
      notifyDataChanged();
      toast.success(
        "Settings saved",
        "Your name and planning preferences are updated.",
      );
    } catch {
      setError("Couldn’t save your settings. Your changes are still here.");
    } finally {
      setBusy(false);
    }
  }

  async function download() {
    if (busy) return;
    setBusy(true);
    try {
      const records = await exportAccount();
      const url = URL.createObjectURL(
        new Blob(
          [
            JSON.stringify(
              {
                ...records,
                profile: {
                  name: displayName,
                  email,
                  preferences: readPreferences(metadata),
                },
              },
              null,
              2,
            ),
          ],
          { type: "application/json" },
        ),
      );
      const a = document.createElement("a");
      a.href = url;
      a.download = `habittrace-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast.success(
        "Export downloaded",
        "Includes your saved plans and execution records.",
      );
    } catch {
      toast.error(
        "Export failed",
        "No incomplete export was downloaded. Please try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function onPickAvatar(file: File | undefined) {
    if (!file || avatarBusy) return;
    setAvatarBusy(true);
    try {
      await uploadUserAvatar(userId, file);
      notifyDataChanged();
      setAvatarMenuOpen(false);
      toast.success("Profile picture updated");
    } catch (caught) {
      toast.error(
        "Upload failed",
        caught instanceof Error
          ? caught.message
          : "Couldn’t upload that picture.",
      );
    } finally {
      setAvatarBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  async function resetAvatar() {
    if (avatarBusy) return;
    setAvatarBusy(true);
    try {
      await clearUserAvatar(userId);
      notifyDataChanged();
      setAvatarMenuOpen(false);
      toast.success(
        "Profile picture reset",
        "Using your default avatar again.",
      );
    } catch {
      toast.error("Couldn’t reset picture", "Please try again.");
    } finally {
      setAvatarBusy(false);
    }
  }

  async function handleSignOut() {
    setSigningOut(true);
    try {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      setConfirmSignOut(false);
      router.replace("/login");
    } catch {
      toast.error("Couldn’t sign out");
      setSigningOut(false);
    }
  }

  return (
    <div className="max-w-3xl space-y-6">
      <header>
        <h1 className="text-3xl font-bold">Your preferences</h1>
        <p className="mt-2 text-slate-500">Make planning fit your day.</p>
      </header>
      <form onSubmit={save} className="panel space-y-5">
        <h2 className="text-lg font-semibold">Profile & planning</h2>

        <div className="relative w-fit" ref={menuRef}>
          <button
            aria-expanded={avatarMenuOpen}
            aria-haspopup="menu"
            aria-label="Change profile picture"
            className="grid h-20 w-20 place-items-center overflow-hidden rounded-full bg-slate-950 text-lg font-bold text-white ring-2 ring-slate-200 transition hover:ring-slate-400"
            disabled={avatarBusy || busy}
            onClick={() => setAvatarMenuOpen((open) => !open)}
            type="button"
          >
            {showImage ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                alt=""
                className="h-full w-full object-cover"
                onError={() => setImageBroken(true)}
                src={avatarUrl!}
              />
            ) : (
              initials
            )}
          </button>
          {avatarMenuOpen && (
            <div
              className="absolute left-0 top-full z-20 mt-2 w-56 rounded-2xl border border-slate-200 bg-white p-2 shadow-xl"
              role="menu"
            >
              <button
                className="flex w-full items-center rounded-xl px-3 py-2.5 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 disabled:opacity-60"
                disabled={avatarBusy}
                onClick={() => fileRef.current?.click()}
                role="menuitem"
                type="button"
              >
                {avatarBusy ? "Working…" : "Upload new picture"}
              </button>
              <button
                className="flex w-full items-center rounded-xl px-3 py-2.5 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 disabled:opacity-60"
                disabled={avatarBusy || !hasCustomAvatar}
                onClick={() => void resetAvatar()}
                role="menuitem"
                type="button"
              >
                Set back to default
              </button>
            </div>
          )}
          <input
            accept="image/*"
            className="hidden"
            onChange={(event) => void onPickAvatar(event.target.files?.[0])}
            ref={fileRef}
            type="file"
          />
        </div>
        <p className="text-sm text-slate-500">
          Click your picture to upload a new one or restore the default.
        </p>

        <label className="block text-sm font-medium">
          Display name
          <input
            required
            maxLength={80}
            className="field mt-2"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <p className="text-sm text-slate-500">Signed in as {email}</p>
        <label className="block text-sm font-medium">
          Default plan duration (minutes)
          <input
            required
            type="number"
            min={5}
            max={480}
            className="field mt-2"
            value={preferences.defaultDuration}
            onChange={(e) =>
              setPreferences((p) => ({
                ...p,
                defaultDuration: Number(e.target.value),
              }))
            }
          />
        </label>
        <div>
          <p className="text-sm font-medium">Daily availability</p>
          <p className="mt-1 text-sm text-slate-500">
            Find a time only suggests slots inside this window. You can still add
            plans outside it manually.
          </p>
          <div className="mt-3 grid grid-cols-2 gap-4">
            <label className="text-sm font-medium">
              From
              <input
                required
                type="time"
                className="field mt-2"
                value={preferences.workStart}
                onChange={(e) =>
                  setPreferences((p) => ({ ...p, workStart: e.target.value }))
                }
              />
            </label>
            <label className="text-sm font-medium">
              Until
              <input
                required
                type="time"
                className="field mt-2"
                value={preferences.workEnd}
                onChange={(e) =>
                  setPreferences((p) => ({ ...p, workEnd: e.target.value }))
                }
              />
            </label>
          </div>
        </div>
        <p className="text-sm text-slate-500">
          Times use your device’s time zone:{" "}
          {Intl.DateTimeFormat().resolvedOptions().timeZone}.
        </p>
        {error && (
          <p role="alert" className="text-sm text-rose-700">
            {error}
          </p>
        )}
        <button disabled={busy || avatarBusy} className="btn-primary" type="submit">
          {busy ? "Working…" : "Save preferences"}
        </button>
      </form>
      <section className="panel">
        <h2 className="text-lg font-semibold">Connected calendars</h2>
        <p className="my-3 text-sm text-slate-500">
          Choose whether to send your plans to Google Calendar. Importing
          external events is not currently supported.
        </p>
        <Link className="btn-secondary" href="/dashboard/integrations">
          Manage connections
        </Link>
      </section>
      <section className="panel">
        <h2 className="text-lg font-semibold">Your records</h2>
        <p className="my-3 text-sm text-slate-500">
          Download your personal plans, execution history and saved profile
          preferences as JSON. Group and AI research records are not included in
          this export.
        </p>
        <button
          className="btn-secondary"
          disabled={busy || avatarBusy}
          onClick={() => void download()}
        >
          Download records
        </button>
      </section>
      <button
        className="btn-secondary !text-rose-700"
        disabled={busy || avatarBusy || signingOut}
        onClick={() => setConfirmSignOut(true)}
        type="button"
      >
        Sign out
      </button>

      {confirmSignOut && (
        <Dialog
          busy={signingOut}
          onClose={() => {
            if (!signingOut) setConfirmSignOut(false);
          }}
          title="Sign out?"
        >
          <p className="mb-5 text-sm leading-relaxed text-slate-600">
            You’ll need to sign in again to see your plans and groups.
          </p>
          <div className="flex gap-3">
            <button
              className="btn-secondary flex-1"
              disabled={signingOut}
              onClick={() => setConfirmSignOut(false)}
              type="button"
            >
              Cancel
            </button>
            <button
              className="btn-primary flex-1 !bg-rose-700"
              disabled={signingOut}
              onClick={() => void handleSignOut()}
              type="button"
            >
              {signingOut ? "Signing out…" : "Sign out"}
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}
