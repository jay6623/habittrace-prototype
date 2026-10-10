"use client";

import { useCallback, useEffect, useState } from "react";
import {
  createGroupAnnouncement,
  getGroupAnnouncements,
  replyToGroupAnnouncement,
  type GroupAnnouncement,
  type GroupRole,
} from "@/lib/api";
import { describeApiError, memberName } from "@/lib/group";
import Dialog from "@/components/ui/dialog";
import MemberAvatar from "@/components/group/member-avatar";

const PAGE_SIZE = 4;
const primaryButton =
  "px-4 py-2 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60";
const secondaryButton =
  "px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm font-medium transition-colors disabled:opacity-60";

function authorLabel(
  author: {
    author_id: string;
    author_name: string | null;
  },
  currentUserId?: string | null
): string {
  return memberName(
    { user_id: author.author_id, display_name: author.author_name },
    currentUserId
  );
}

function postedAt(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export default function GroupAnnouncements({
  groupId,
  role,
  currentUserId,
}: {
  groupId: string;
  role: GroupRole;
  currentUserId?: string | null;
}) {
  const canPost = role === "owner" || role === "admin";
  const [announcements, setAnnouncements] = useState<GroupAnnouncement[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [posting, setPosting] = useState(false);
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [replyDraft, setReplyDraft] = useState("");
  const [replying, setReplying] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setAnnouncements(await getGroupAnnouncements(groupId));
    } catch (caught) {
      setError(describeApiError(caught, "We couldn't load announcements."));
    } finally {
      setLoading(false);
    }
  }, [groupId]);

  useEffect(() => {
    setCreating(false);
    setTitle("");
    setDescription("");
    setPage(1);
    setSelectedId(null);
    setReplyDraft("");
    void load();
  }, [load]);

  const pageCount = Math.max(1, Math.ceil(announcements.length / PAGE_SIZE));
  const currentPage = Math.min(page, pageCount);
  const visible = announcements.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE
  );
  const selected =
    announcements.find((announcement) => announcement.id === selectedId) ?? null;

  async function postAnnouncement() {
    const nextTitle = title.trim();
    const nextBody = description.trim();
    if (!nextTitle || !nextBody || posting) return;
    setPosting(true);
    setError(null);
    try {
      const created = await createGroupAnnouncement(groupId, {
        title: nextTitle,
        body: nextBody,
      });
      setAnnouncements((current) => [created, ...current]);
      setTitle("");
      setDescription("");
      setCreating(false);
      setPage(1);
    } catch (caught) {
      setError(describeApiError(caught, "We couldn't post that announcement."));
    } finally {
      setPosting(false);
    }
  }

  async function postReply() {
    if (!selected) return;
    const body = replyDraft.trim();
    if (!body || replying) return;
    setReplying(true);
    setError(null);
    try {
      const reply = await replyToGroupAnnouncement(groupId, selected.id, body);
      setAnnouncements((current) =>
        current.map((announcement) =>
          announcement.id === selected.id
            ? { ...announcement, replies: [...announcement.replies, reply] }
            : announcement
        )
      );
      setReplyDraft("");
    } catch (caught) {
      setError(describeApiError(caught, "We couldn't post that reply."));
    } finally {
      setReplying(false);
    }
  }

  return (
    <section className="bg-white rounded-2xl border border-slate-200 p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">Announcements</h2>
          <p className="mt-1 text-sm text-slate-500">
            {canPost
              ? "Members can open a thread to reply."
              : "Only the owner or an admin can post. Open an announcement to read it and reply."}
          </p>
        </div>
        {canPost && !creating && (
          <button
            className={primaryButton}
            onClick={() => setCreating(true)}
            type="button"
          >
            Create announcement
          </button>
        )}
      </div>

      {canPost && creating && (
        <form
          className="mt-4 grid gap-3"
          onSubmit={(event) => {
            event.preventDefault();
            void postAnnouncement();
          }}
        >
          <input
            className="field"
            maxLength={120}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="Announcement title"
            value={title}
          />
          <textarea
            className="field resize-y"
            maxLength={2000}
            onChange={(event) => setDescription(event.target.value)}
            placeholder="Description"
            style={{ minHeight: "5rem" }}
            value={description}
          />
          <div className="flex gap-2">
            <button
              className={primaryButton}
              disabled={posting || !title.trim() || !description.trim()}
              type="submit"
            >
              {posting ? "Posting…" : "Post announcement"}
            </button>
            <button
              className={secondaryButton}
              disabled={posting}
              onClick={() => {
                setCreating(false);
                setTitle("");
                setDescription("");
              }}
              type="button"
            >
              Cancel
            </button>
          </div>
        </form>
      )}

      {error && (
        <div className="mt-4 rounded-xl border border-rose-100 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {error}
        </div>
      )}

      {loading ? (
        <p className="mt-4 text-sm text-slate-400 animate-pulse">Loading announcements…</p>
      ) : announcements.length === 0 ? (
        <p className="mt-4 text-sm text-slate-500">No announcements yet.</p>
      ) : (
        <>
          <ul className="mt-4 divide-y divide-slate-100 rounded-xl border border-slate-200">
            {visible.map((announcement) => {
              const name = authorLabel(announcement, currentUserId);
              return (
                <li key={announcement.id}>
                  <button
                    className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left hover:bg-slate-50"
                    onClick={() => {
                      setSelectedId(announcement.id);
                      setReplyDraft("");
                    }}
                    type="button"
                  >
                    <span className="min-w-0 truncate font-medium">{announcement.title}</span>
                    <span className="flex shrink-0 items-center gap-2 text-sm text-slate-500">
                      <MemberAvatar
                        avatarUrl={announcement.author_avatar_url}
                        className="h-7 w-7 text-xs"
                        name={name}
                      />
                      {name}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
          {announcements.length > PAGE_SIZE && (
            <nav aria-label="Announcement pages" className="mt-3 flex flex-wrap gap-1">
              {Array.from({ length: pageCount }, (_, index) => index + 1).map((number) => (
                <button
                  aria-current={number === currentPage ? "page" : undefined}
                  className={`h-8 min-w-8 rounded-lg px-2 text-sm font-medium ${
                    number === currentPage
                      ? "bg-slate-900 text-white"
                      : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                  }`}
                  key={number}
                  onClick={() => setPage(number)}
                  type="button"
                >
                  {number}
                </button>
              ))}
            </nav>
          )}
        </>
      )}

      {selected && (
        <Dialog onClose={() => setSelectedId(null)} title={selected.title}>
          <div className="mb-4 flex items-center gap-3">
            <MemberAvatar
              avatarUrl={selected.author_avatar_url}
              className="h-9 w-9 text-xs"
              name={authorLabel(selected, currentUserId)}
            />
            <div>
              <div className="text-sm font-medium">
                {authorLabel(selected, currentUserId)}
              </div>
              <div className="text-xs text-slate-400">{postedAt(selected.created_at)}</div>
            </div>
          </div>
          <p className="whitespace-pre-wrap text-sm text-slate-700">{selected.body}</p>
          <div className="mt-5 space-y-3">
            <div className="text-sm font-semibold">Replies</div>
            {selected.replies.length === 0 ? (
              <p className="text-sm text-slate-500">No replies yet.</p>
            ) : (
              selected.replies.map((reply) => {
                const replyName = authorLabel(reply, currentUserId);
                return (
                  <div key={reply.id} className="flex items-start gap-3">
                    <MemberAvatar
                      avatarUrl={reply.author_avatar_url}
                      className="h-8 w-8 text-xs"
                      name={replyName}
                    />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-baseline gap-x-2">
                        <span className="text-sm font-medium">{replyName}</span>
                        <span className="text-xs text-slate-400">{postedAt(reply.created_at)}</span>
                      </div>
                      <p className="mt-1 whitespace-pre-wrap text-sm text-slate-700">
                        {reply.body}
                      </p>
                    </div>
                  </div>
                );
              })
            )}
          </div>
          <form
            className="mt-4 flex flex-col gap-2 sm:flex-row"
            onSubmit={(event) => {
              event.preventDefault();
              void postReply();
            }}
          >
            <input
              className="field sm:flex-1"
              maxLength={2000}
              onChange={(event) => setReplyDraft(event.target.value)}
              placeholder="Write a reply…"
              value={replyDraft}
            />
            <button
              className={secondaryButton}
              disabled={replying || !replyDraft.trim()}
              type="submit"
            >
              {replying ? "Replying…" : "Reply"}
            </button>
          </form>
        </Dialog>
      )}
    </section>
  );
}
