"use client";

import { FormEvent, useState } from "react";
import {
  GROUP_NAME_MAX_LENGTH,
  INVITE_CODE_LENGTH,
  INVITE_CODE_PATTERN,
  describeApiError,
  normalizeInviteCode,
} from "@/lib/group";

interface GroupSetupProps {
  /** "empty" fills the page when the user has no groups; "panel" is an inline card. */
  mode: "empty" | "panel";
  onCreate: (name: string) => Promise<void>;
  onJoin: (inviteCode: string) => Promise<void>;
  onDismiss?: () => void;
}

const inputClass =
  "min-h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-4 text-sm text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100";
const primaryButtonClass =
  "px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60";

export default function GroupSetup({ mode, onCreate, onJoin, onDismiss }: GroupSetupProps) {
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const [code, setCode] = useState("");
  const [joining, setJoining] = useState(false);
  const [joinError, setJoinError] = useState<string | null>(null);

  const busy = creating || joining;

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setCreateError("Enter a group name.");
      return;
    }
    if (trimmed.length > GROUP_NAME_MAX_LENGTH) {
      setCreateError(`Keep the name under ${GROUP_NAME_MAX_LENGTH} characters.`);
      return;
    }
    setCreating(true);
    setCreateError(null);
    try {
      await onCreate(trimmed);
      setName("");
    } catch (caught) {
      setCreateError(describeApiError(caught, "We couldn't create the group. Try again."));
    } finally {
      setCreating(false);
    }
  }

  async function handleJoin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalized = normalizeInviteCode(code);
    if (!INVITE_CODE_PATTERN.test(normalized)) {
      setJoinError(`Invite codes are ${INVITE_CODE_LENGTH} letters or digits.`);
      return;
    }
    setJoining(true);
    setJoinError(null);
    try {
      await onJoin(normalized);
      setCode("");
    } catch (caught) {
      setJoinError(describeApiError(caught, "We couldn't join that group. Try again."));
    } finally {
      setJoining(false);
    }
  }

  return (
    <section
      aria-labelledby="group-setup-title"
      className={`bg-white rounded-2xl border p-5 ${
        mode === "empty" ? "border-slate-200" : "border-violet-200"
      }`}
    >
      <div className="flex items-start justify-between gap-4 mb-4">
        <div>
          <h2 id="group-setup-title" className="font-semibold">
            {mode === "empty" ? "Start with a group" : "New or existing group"}
          </h2>
          <p className="text-sm text-slate-500">
            {mode === "empty"
              ? "Create a group for your team, or join one with an invite code."
              : "Create another group or join one with an invite code."}
          </p>
        </div>
        {onDismiss && (
          <button
            aria-label="Close"
            className="grid h-9 w-9 place-items-center rounded-full bg-slate-100 text-lg text-slate-600 transition hover:bg-slate-200 disabled:opacity-50"
            disabled={busy}
            onClick={onDismiss}
            type="button"
          >
            ×
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <form onSubmit={handleCreate} className="rounded-2xl border border-slate-100 p-4 space-y-3">
          <label className="block text-sm font-semibold text-slate-800" htmlFor="group-name">
            Create a group
          </label>
          <input
            id="group-name"
            className={inputClass}
            maxLength={GROUP_NAME_MAX_LENGTH}
            onChange={(event) => setName(event.target.value)}
            placeholder="e.g. Study & Work Group"
            value={name}
            disabled={busy}
          />
          {createError && (
            <p className="rounded-xl bg-rose-50 px-3 py-2 text-sm font-medium text-rose-700" role="alert">
              {createError}
            </p>
          )}
          <button className={primaryButtonClass} disabled={busy} type="submit">
            {creating ? "Creating…" : "Create group"}
          </button>
        </form>

        <form onSubmit={handleJoin} className="rounded-2xl border border-slate-100 p-4 space-y-3">
          <label className="block text-sm font-semibold text-slate-800" htmlFor="invite-code">
            Join with an invite code
          </label>
          <input
            id="invite-code"
            autoCapitalize="characters"
            autoComplete="off"
            className={`${inputClass} font-mono tracking-widest uppercase`}
            maxLength={INVITE_CODE_LENGTH}
            onChange={(event) => setCode(normalizeInviteCode(event.target.value))}
            placeholder="ABCD2345"
            spellCheck={false}
            value={code}
            disabled={busy}
          />
          {joinError && (
            <p className="rounded-xl bg-rose-50 px-3 py-2 text-sm font-medium text-rose-700" role="alert">
              {joinError}
            </p>
          )}
          <button className={primaryButtonClass} disabled={busy} type="submit">
            {joining ? "Joining…" : "Join group"}
          </button>
        </form>
      </div>
    </section>
  );
}
