"use client";

import { FormEvent, useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/app/providers";
import Dialog from "@/components/ui/dialog";
import { useToast } from "@/components/ui/toast";
import {
  avatarInitials,
  readAvatarUrl,
  uploadUserAvatar,
} from "@/lib/avatar";
import { syncProfileDisplayName } from "@/lib/profile";
import { notifyDataChanged } from "@/lib/refresh";
import { supabase } from "@/lib/supabase";

type ProfileMenuTone = "light" | "dark";

export default function ProfileMenu({
  tone = "light",
  size = "md",
  menuPlacement = "up",
  className = "",
}: {
  tone?: ProfileMenuTone;
  size?: "sm" | "md" | "lg";
  menuPlacement?: "up" | "down";
  className?: string;
}) {
  const { user, displayName } = useAuth();
  const router = useRouter();
  const toast = useToast();
  const menuId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const [open, setOpen] = useState(false);
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(displayName);
  const [savingName, setSavingName] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [confirmSignOut, setConfirmSignOut] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [imageBroken, setImageBroken] = useState(false);

  const avatarUrl = readAvatarUrl(user);
  const initials = avatarInitials(displayName, user?.email);
  const showImage = Boolean(avatarUrl) && !imageBroken;

  useEffect(() => {
    setImageBroken(false);
  }, [avatarUrl]);

  useEffect(() => {
    setName(displayName);
  }, [displayName]);

  useEffect(() => {
    if (!open) return;
    function onPointer(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
        setEditingName(false);
      }
    }
    document.addEventListener("mousedown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  if (!user) return null;

  const dimension =
    size === "lg" ? "h-14 w-14 text-base" : size === "sm" ? "h-9 w-9 text-xs" : "h-11 w-11 text-sm";

  const ring =
    tone === "dark"
      ? "ring-white/25 hover:ring-white/50"
      : "ring-slate-200 hover:ring-slate-400";

  async function saveDisplayName(event: FormEvent) {
    event.preventDefault();
    const nextName = name.trim();
    if (!nextName) {
      setError("Enter a display name.");
      return;
    }
    setSavingName(true);
    setError(null);
    try {
      const { error: updateError } = await supabase.auth.updateUser({
        data: { first_name: nextName },
      });
      if (updateError) throw updateError;
      await syncProfileDisplayName(user.id, nextName);
      notifyDataChanged();
      setEditingName(false);
      toast.success("Display name updated", nextName);
    } catch {
      setError("Couldn’t update your name. Please try again.");
    } finally {
      setSavingName(false);
    }
  }

  async function onPickFile(file: File | undefined) {
    if (!file) return;
    setUploading(true);
    setError(null);
    try {
      await uploadUserAvatar(user.id, file);
      notifyDataChanged();
      toast.success("Profile picture updated");
      setOpen(false);
    } catch (caught) {
      setError(
        caught instanceof Error
          ? caught.message
          : "Couldn’t upload that picture. Please try again.",
      );
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  async function handleSignOut() {
    setSigningOut(true);
    try {
      const { error: signOutError } = await supabase.auth.signOut();
      if (signOutError) throw signOutError;
      setConfirmSignOut(false);
      setOpen(false);
      router.replace("/login");
    } catch {
      toast.error("Couldn’t sign out", "Please try again.");
      setSigningOut(false);
    }
  }

  return (
    <>
      <div className={`relative ${className}`} ref={rootRef}>
        <button
          aria-controls={menuId}
          aria-expanded={open}
          aria-haspopup="menu"
          aria-label="Open profile menu"
          className={`grid shrink-0 place-items-center overflow-hidden rounded-full bg-slate-950 font-bold text-white ring-2 transition ${dimension} ${ring}`}
          onClick={() => {
            setOpen((value) => !value);
            setEditingName(false);
            setError(null);
          }}
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
            <span aria-hidden="true">{initials}</span>
          )}
        </button>

        {open && (
          <div
            className={`absolute z-50 w-72 rounded-2xl border border-slate-200 bg-white p-3 text-slate-950 shadow-xl ${
              menuPlacement === "down"
                ? "left-auto right-0 top-full mt-3 origin-top-right"
                : "bottom-full left-0 mb-3 origin-bottom-left sm:left-auto sm:right-0 sm:origin-bottom-right"
            }`}
            id={menuId}
            role="menu"
          >
            <div className="flex items-center gap-3 rounded-xl bg-slate-50 px-3 py-3">
              <div className="grid h-12 w-12 shrink-0 place-items-center overflow-hidden rounded-full bg-slate-950 text-sm font-bold text-white">
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
              </div>
              <div className="min-w-0">
                <p className="truncate font-semibold">{displayName}</p>
                <p className="truncate text-xs text-slate-500">{user.email}</p>
              </div>
            </div>

            {error && (
              <p className="mt-3 rounded-xl bg-rose-50 px-3 py-2 text-xs font-medium text-rose-700" role="alert">
                {error}
              </p>
            )}

            {editingName ? (
              <form className="mt-3 space-y-2" onSubmit={saveDisplayName}>
                <label className="block text-xs font-semibold text-slate-600" htmlFor={`${menuId}-name`}>
                  Display name
                </label>
                <input
                  autoFocus
                  className="field !py-2 text-sm"
                  disabled={savingName}
                  id={`${menuId}-name`}
                  maxLength={80}
                  onChange={(event) => setName(event.target.value)}
                  value={name}
                />
                <div className="flex gap-2">
                  <button
                    className="btn-secondary flex-1 !py-2 text-sm"
                    disabled={savingName}
                    onClick={() => {
                      setEditingName(false);
                      setName(displayName);
                      setError(null);
                    }}
                    type="button"
                  >
                    Cancel
                  </button>
                  <button
                    className="btn-primary flex-1 !py-2 text-sm"
                    disabled={savingName}
                    type="submit"
                  >
                    {savingName ? "Saving…" : "Save"}
                  </button>
                </div>
              </form>
            ) : (
              <div className="mt-2 space-y-1">
                <button
                  className="flex w-full items-center rounded-xl px-3 py-2.5 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100"
                  onClick={() => {
                    setEditingName(true);
                    setError(null);
                  }}
                  role="menuitem"
                  type="button"
                >
                  Change display name
                </button>
                <button
                  className="flex w-full items-center rounded-xl px-3 py-2.5 text-left text-sm font-medium text-slate-700 transition hover:bg-slate-100 disabled:opacity-60"
                  disabled={uploading}
                  onClick={() => fileRef.current?.click()}
                  role="menuitem"
                  type="button"
                >
                  {uploading ? "Uploading picture…" : "Upload profile picture"}
                </button>
                <button
                  className="flex w-full items-center rounded-xl px-3 py-2.5 text-left text-sm font-medium text-rose-700 transition hover:bg-rose-50"
                  onClick={() => {
                    setConfirmSignOut(true);
                    setOpen(false);
                  }}
                  role="menuitem"
                  type="button"
                >
                  Sign out
                </button>
              </div>
            )}

            <input
              accept="image/*"
              className="hidden"
              onChange={(event) => void onPickFile(event.target.files?.[0])}
              ref={fileRef}
              type="file"
            />
          </div>
        )}
      </div>

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
    </>
  );
}
