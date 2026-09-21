"use client";

import { FormEvent, useState } from "react";
import Dialog from "@/components/ui/dialog";
import {
  GROUP_NAME_MAX_LENGTH,
  INVITE_CODE_LENGTH,
  INVITE_CODE_PATTERN,
  describeApiError,
  normalizeInviteCode,
} from "@/lib/group";

interface GroupSetupProps {
  /** "empty" is the no-groups landing; "panel" is used when adding another group. */
  mode: "empty" | "panel";
  onCreate: (name: string) => Promise<void>;
  onJoin: (inviteCode: string) => Promise<void>;
  onDismiss?: () => void;
}

type SetupDialog = "create" | "join" | null;

const inputClass =
  "min-h-11 w-full rounded-xl border border-slate-200 bg-slate-50 px-4 text-sm text-slate-950 outline-none transition placeholder:text-slate-400 focus:border-slate-500 focus:bg-white focus:ring-4 focus:ring-slate-100";
const primaryButtonClass =
  "mt-2 w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60";

export default function GroupSetup({
  mode,
  onCreate,
  onJoin,
  onDismiss,
}: GroupSetupProps) {
  const [dialog, setDialog] = useState<SetupDialog>(null);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const [code, setCode] = useState("");
  const [joining, setJoining] = useState(false);
  const [joinError, setJoinError] = useState<string | null>(null);

  const busy = creating || joining;

  function openDialog(next: SetupDialog) {
    setCreateError(null);
    setJoinError(null);
    setDialog(next);
  }

  function closeDialog() {
    if (busy) return;
    setDialog(null);
    setCreateError(null);
    setJoinError(null);
  }

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
      setDialog(null);
      onDismiss?.();
    } catch (caught) {
      setCreateError(
        describeApiError(caught, "We couldn't create the group. Try again."),
      );
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
      setDialog(null);
      onDismiss?.();
    } catch (caught) {
      setJoinError(
        describeApiError(caught, "We couldn't join that group. Try again."),
      );
    } finally {
      setJoining(false);
    }
  }

  const chooser =
    mode === "empty" ? (
      <section className="mx-auto max-w-3xl py-6">
        <div className="mb-8 text-center">
          <h2 className="text-2xl font-bold tracking-tight text-slate-950">
            Start coordinating together
          </h2>
          <p className="mx-auto mt-3 max-w-lg text-sm leading-relaxed text-slate-500">
            Create a shared space for your team, or join an existing group with
            an invite code.
          </p>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <button
            className="group flex min-h-44 flex-col items-start justify-between rounded-[1.75rem] border border-slate-200 bg-white p-6 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md"
            onClick={() => openDialog("create")}
            type="button"
          >
            <span className="grid h-12 w-12 place-items-center rounded-2xl bg-slate-950 text-lg font-bold text-white">
              +
            </span>
            <span>
              <span className="block text-xl font-bold text-slate-950">
                Create group
              </span>
              <span className="mt-2 block text-sm leading-relaxed text-slate-500">
                Start a new group and invite teammates when you&apos;re ready.
              </span>
            </span>
          </button>
          <button
            className="group flex min-h-44 flex-col items-start justify-between rounded-[1.75rem] border border-slate-200 bg-gradient-to-br from-slate-50 to-white p-6 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-md"
            onClick={() => openDialog("join")}
            type="button"
          >
            <span className="grid h-12 w-12 place-items-center rounded-2xl bg-emerald-600 text-lg font-bold text-white">
              ↗
            </span>
            <span>
              <span className="block text-xl font-bold text-slate-950">
                Join group
              </span>
              <span className="mt-2 block text-sm leading-relaxed text-slate-500">
                Enter an invite code from a teammate to get access.
              </span>
            </span>
          </button>
        </div>
      </section>
    ) : (
      <section className="rounded-2xl border border-slate-200 bg-white p-5">
        <div className="mb-4 flex items-start justify-between gap-4">
          <div>
            <h2 className="font-semibold">New or existing group</h2>
            <p className="text-sm text-slate-500">
              Create another group or join one with an invite code.
            </p>
          </div>
          {onDismiss && (
            <button
              aria-label="Close"
              className="grid h-9 w-9 place-items-center rounded-full bg-slate-100 text-lg text-slate-600 transition hover:bg-slate-200"
              onClick={onDismiss}
              type="button"
            >
              ×
            </button>
          )}
        </div>
        <div className="grid gap-3 sm:grid-cols-2">
          <button
            className="rounded-2xl border border-slate-200 bg-slate-950 px-5 py-4 text-left text-white transition hover:bg-slate-800"
            onClick={() => openDialog("create")}
            type="button"
          >
            <span className="block text-base font-bold">Create group</span>
            <span className="mt-1 block text-sm text-slate-300">
              Make a new shared workspace
            </span>
          </button>
          <button
            className="rounded-2xl border border-slate-200 bg-white px-5 py-4 text-left transition hover:bg-slate-50"
            onClick={() => openDialog("join")}
            type="button"
          >
            <span className="block text-base font-bold text-slate-950">
              Join group
            </span>
            <span className="mt-1 block text-sm text-slate-500">
              Use a teammate&apos;s invite code
            </span>
          </button>
        </div>
      </section>
    );

  return (
    <>
      {chooser}

      {dialog === "create" && (
        <Dialog busy={busy} onClose={closeDialog} title="Create a group">
          <p className="mb-5 text-sm leading-relaxed text-slate-500">
            Give your group a clear name. You&apos;ll get an invite code to share
            so teammates can join.
          </p>
          <form className="space-y-3" onSubmit={handleCreate}>
            <label
              className="block text-sm font-semibold text-slate-800"
              htmlFor="group-name"
            >
              Group name
            </label>
            <input
              autoFocus
              className={inputClass}
              disabled={busy}
              id="group-name"
              maxLength={GROUP_NAME_MAX_LENGTH}
              onChange={(event) => setName(event.target.value)}
              placeholder="e.g. Study & Work Group"
              value={name}
            />
            {createError && (
              <p
                className="rounded-xl bg-rose-50 px-3 py-2 text-sm font-medium text-rose-700"
                role="alert"
              >
                {createError}
              </p>
            )}
            <button className={primaryButtonClass} disabled={busy} type="submit">
              {creating ? "Creating…" : "Create group"}
            </button>
          </form>
        </Dialog>
      )}

      {dialog === "join" && (
        <Dialog busy={busy} onClose={closeDialog} title="Join a group">
          <p className="mb-5 text-sm leading-relaxed text-slate-500">
            Ask a group owner for their invite code, then enter it here to join
            their shared tasks.
          </p>
          <form className="space-y-3" onSubmit={handleJoin}>
            <label
              className="block text-sm font-semibold text-slate-800"
              htmlFor="invite-code"
            >
              Invite code
            </label>
            <input
              autoCapitalize="characters"
              autoComplete="off"
              autoFocus
              className={`${inputClass} font-mono tracking-widest uppercase`}
              disabled={busy}
              id="invite-code"
              maxLength={INVITE_CODE_LENGTH}
              onChange={(event) =>
                setCode(normalizeInviteCode(event.target.value))
              }
              placeholder="ABCD2345"
              spellCheck={false}
              value={code}
            />
            {joinError && (
              <p
                className="rounded-xl bg-rose-50 px-3 py-2 text-sm font-medium text-rose-700"
                role="alert"
              >
                {joinError}
              </p>
            )}
            <button className={primaryButtonClass} disabled={busy} type="submit">
              {joining ? "Joining…" : "Join group"}
            </button>
          </form>
        </Dialog>
      )}
    </>
  );
}
