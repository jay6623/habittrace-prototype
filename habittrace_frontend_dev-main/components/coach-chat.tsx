"use client";

import { useState, useRef, useEffect } from "react";
import {
  archiveCoachConversation,
  confirmCoachProposal,
  dismissCoachProposal,
  getLatestCoachConversation,
  streamChatEvents,
  type ChatMessage,
  type CoachProposal,
  type TaskCreate,
} from "@/lib/api";

// ── Suggestion chips shown at start ──────────────────────────────────────────
const SUGGESTIONS = [
  "Why do my Study tasks keep failing?",
  "What's my best time to schedule deep work?",
  "How can I reduce interruptions?",
  "Give me a tip based on my patterns",
];

// ── Category options ──────────────────────────────────────────────────────────
const CATEGORIES = ["Study", "Work", "Exercise", "Personal", "Other"];

// ── Markdown-lite: bold **text** and newlines ─────────────────────────────────
function renderContent(text: string) {
  return text.split("\n").map((line, i, arr) => {
    const parts = line.split(/\*\*(.*?)\*\*/g);
    return (
      <span key={i}>
        {parts.map((p, j) =>
          j % 2 === 1 ? <strong key={j}>{p}</strong> : p
        )}
        {i < arr.length - 1 && <br />}
      </span>
    );
  });
}

// ── Editable confirm card ─────────────────────────────────────────────────────
function TaskConfirmCard({
  proposal,
  onConfirm,
  onCancel,
}: {
  proposal: CoachProposal;
  onConfirm: (candidateStart: string, task: TaskCreate) => Promise<void>;
  onCancel: () => Promise<void>;
}) {
  const [selectedStart, setSelectedStart] = useState(proposal.options[0]?.start ?? "");
  const [form, setForm] = useState<TaskCreate>({ ...proposal.task });
  const [loading, setLoading] = useState(false);

  function set<K extends keyof TaskCreate>(key: K, val: TaskCreate[K]) {
    setForm((prev) => ({ ...prev, [key]: val }));
  }

  async function handleConfirm() {
    setLoading(true);
    try {
      await onConfirm(selectedStart, form);
    } finally {
      setLoading(false);
    }
  }

  function selectOption(start: string) {
    setSelectedStart(start);
    const value = new Date(start);
    setForm((prev) => ({
      ...prev,
      planned_date: start.slice(0, 10),
      planned_start_time: `${String(value.getHours()).padStart(2, "0")}:${String(value.getMinutes()).padStart(2, "0")}`,
    }));
  }

  return (
    <div className="mt-3 bg-slate-50 border border-slate-200 rounded-xl p-3 space-y-3">
      <div className="text-xs font-semibold text-slate-500 uppercase tracking-wide">
        Choose a recommended time
      </div>

      <div className="space-y-2">
        {proposal.options.map((option, index) => {
          const selected = selectedStart === option.start;
          const start = new Date(option.start);
          const end = new Date(option.end);
          return (
            <button
              type="button"
              key={option.start}
              onClick={() => selectOption(option.start)}
              className={`w-full text-left rounded-lg border p-3 transition-colors ${selected ? "border-slate-900 bg-white" : "border-slate-200 bg-slate-50 hover:bg-white"}`}
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-semibold text-slate-800">
                  {index === 0 ? "Best fit · " : ""}
                  {start.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}–{end.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}
                </span>
                <span className="text-xs font-medium text-emerald-700">
                  {Math.round(option.score * 100)}% fit
                </span>
              </div>
              <div className="mt-1 text-xs text-slate-500">{option.reasons[0]}</div>
            </button>
          );
        })}
      </div>

      {/* Title */}
      <div>
        <label className="text-xs text-slate-500 block mb-1">Title</label>
        <input
          className="w-full text-sm bg-white border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-slate-400"
          value={form.title}
          onChange={(e) => set("title", e.target.value)}
        />
      </div>

      {/* Date + Time row */}
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="text-xs text-slate-500 block mb-1">Date</label>
          <input
            type="date"
            className="w-full text-sm bg-white border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-slate-400"
            value={form.planned_date ?? ""}
            onChange={(e) => set("planned_date", e.target.value)}
          />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Time</label>
          <input
            type="time"
            className="w-full text-sm bg-white border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-slate-400"
            value={form.planned_start_time}
            onChange={(e) => set("planned_start_time", e.target.value)}
          />
        </div>
      </div>

      {/* Category + Duration row */}
      <div className="grid grid-cols-2 gap-2">
        <div>
          <label className="text-xs text-slate-500 block mb-1">Category</label>
          <select
            className="w-full text-sm bg-white border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-slate-400"
            value={form.task_category}
            onChange={(e) => set("task_category", e.target.value)}
          >
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Duration (min)</label>
          <input
            type="number"
            min={5}
            max={480}
            step={5}
            className="w-full text-sm bg-white border border-slate-200 rounded-lg px-3 py-2 outline-none focus:border-slate-400"
            value={form.planned_duration_min}
            onChange={(e) => set("planned_duration_min", parseInt(e.target.value, 10) || 60)}
          />
        </div>
      </div>

      {/* Buttons */}
      <div className="flex gap-2 pt-1">
        <button
          onClick={handleConfirm}
          disabled={loading || !form.title.trim()}
          className="flex-1 py-2 rounded-lg bg-slate-900 text-white text-sm font-medium hover:bg-slate-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        >
          {loading ? "Adding…" : "Confirm & Add"}
        </button>
        <button
          onClick={() => void onCancel()}
          disabled={loading}
          className="px-4 py-2 rounded-lg bg-white border border-slate-200 text-slate-600 text-sm hover:bg-slate-50 transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}

// ── Extended message type ─────────────────────────────────────────────────────
interface Message extends ChatMessage {
  proposal?: CoachProposal;
  taskStatus?: "confirmed" | "cancelled";
}

// ── Component ─────────────────────────────────────────────────────────────────
export default function CoachChat() {
  const [messages, setMessages]     = useState<Message[]>([]);
  const [conversationId, setConversationId] = useState<string | undefined>();
  const [loadingHistory, setLoadingHistory] = useState(true);
  const [input, setInput]           = useState("");
  const [streaming, setStreaming]   = useState(false);
  const [streamText, setStreamText] = useState("");
  const [error, setError]           = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const inputRef  = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let active = true;
    getLatestCoachConversation()
      .then((conversation) => {
        if (!active || !conversation) return;
        setConversationId(conversation.id);
        setMessages([
          ...conversation.messages.map((message) => ({
            role: message.role,
            content: message.content,
          })),
          ...conversation.pending_proposals.map((proposal) => ({
            role: "assistant" as const,
            content: "This recommendation is still waiting for your confirmation.",
            proposal,
          })),
        ]);
      })
      .catch(() => {
        // The coach remains usable before persistence is configured.
      })
      .finally(() => {
        if (active) setLoadingHistory(false);
      });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, streamText]);

  async function send(text: string) {
    const trimmed = text.trim();
    if (!trimmed || streaming) return;
    setError(null);
    setInput("");

    const userMsg: Message = { role: "user", content: trimmed };
    const historyForApi: ChatMessage[] = [...messages, userMsg].map((m) => ({
      role: m.role,
      content: m.content,
    }));

    setMessages((prev) => [...prev, userMsg]);
    setStreaming(true);
    setStreamText("");

    try {
      let full = "";
      let proposal: CoachProposal | undefined;

      for await (const event of streamChatEvents(
        trimmed,
        historyForApi.slice(0, -1),
        conversationId,
      )) {
        if (event.type === "token") {
          full += event.token;
          setStreamText(full);
        } else if (event.type === "conversation") {
          setConversationId(event.conversationId);
        } else if (event.type === "proposal") {
          proposal = event.proposal;
        }
      }

      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: full.trimEnd(), proposal },
      ]);
      setStreamText("");
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Unknown error";
      setError(msg);
    } finally {
      setStreaming(false);
      inputRef.current?.focus();
    }
  }

  function confirmTask(msgIdx: number, proposal: CoachProposal) {
    return async (candidateStart: string, edited: TaskCreate) => {
      try {
        await confirmCoachProposal(proposal.id, candidateStart, edited);
        setMessages((prev) =>
          prev.map((m, i) =>
            i === msgIdx ? { ...m, taskStatus: "confirmed" } : m
          )
        );
        // Append success message in chat
        setMessages((prev) => [
          ...prev,
          {
            role: "assistant",
            content: `"${edited.title}" has been added to your schedule on ${edited.planned_date} at ${edited.planned_start_time}. Check your Calendar or Habits tab!`,
          },
        ]);
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : "Failed to add task";
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: `Sorry, couldn't add the task: ${msg}` },
        ]);
      }
    };
  }

  function cancelTask(msgIdx: number, proposal: CoachProposal) {
    return async () => {
      try {
        await dismissCoachProposal(proposal.id);
      } finally {
        setMessages((prev) =>
          prev.map((m, i) =>
            i === msgIdx ? { ...m, taskStatus: "cancelled" } : m
          )
        );
      }
    };
  }

  async function clearConversation() {
    if (conversationId) {
      try {
        await archiveCoachConversation(conversationId);
      } catch {
        // Clear the local view even if persistence is temporarily unavailable.
      }
    }
    setConversationId(undefined);
    setMessages([]);
    setError(null);
  }

  const showWelcome = !loadingHistory && messages.length === 0 && !streaming;

  return (
    <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden flex flex-col h-full">
      {/* Header */}
      <div className="p-5 border-b border-slate-200 shrink-0">
        <div className="flex items-center gap-2">
          <div className="h-7 w-7 rounded-full bg-slate-900 flex items-center justify-center shrink-0">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"
                fill="white" opacity="0.9"/>
            </svg>
          </div>
          <div>
            <div className="font-semibold text-sm">AI Coach</div>
            <div className="text-xs text-slate-500">Powered by Phi-3 Mini · runs locally</div>
          </div>
          <div className="ml-auto flex items-center gap-1.5">
            <div className={`h-2 w-2 rounded-full ${streaming ? "bg-emerald-400 animate-pulse" : "bg-slate-200"}`} />
            <span className="text-xs text-slate-400">{streaming ? "Thinking…" : "Ready"}</span>
          </div>
        </div>
      </div>

      {/* Message area */}
      <div className="flex-1 overflow-y-auto px-5 py-4 space-y-4 bg-slate-50 min-h-0">

        {/* Welcome + suggestions */}
        {showWelcome && (
          <div className="space-y-3">
            <div className="flex gap-3">
              <div className="h-8 w-8 rounded-full bg-slate-900 shrink-0 flex items-center justify-center text-white text-xs font-bold">AI</div>
              <div className="max-w-[85%] bg-white border border-slate-200 rounded-2xl rounded-tl-sm px-4 py-3">
                <div className="text-sm text-slate-700">
                  Hi! I&apos;m your HabitTrace coach. I can see your task history and patterns.
                  Ask me anything, or tell me what you want to schedule — I&apos;ll add it to your calendar!
                </div>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 pl-11">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => send(s)}
                  className="text-xs px-3 py-1.5 rounded-full bg-white border border-slate-200 text-slate-600 hover:bg-slate-900 hover:text-white hover:border-slate-900 transition-colors"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Conversation history */}
        {messages.map((msg, i) => (
          <div key={i} className={`flex gap-3 ${msg.role === "user" ? "flex-row-reverse" : ""}`}>
            {msg.role === "assistant" && (
              <div className="h-8 w-8 rounded-full bg-slate-900 shrink-0 flex items-center justify-center text-white text-xs font-bold">AI</div>
            )}
            <div className={`max-w-[85%] ${msg.role === "user" ? "items-end" : ""}`}>
              <div className={`rounded-2xl px-4 py-3 text-sm ${
                msg.role === "user"
                  ? "bg-slate-900 text-white rounded-tr-sm"
                  : "bg-white border border-slate-200 text-slate-700 rounded-tl-sm"
              }`}>
                {msg.role === "assistant" ? renderContent(msg.content) : msg.content}
              </div>

              {/* Task confirmation card */}
              {msg.role === "assistant" && msg.proposal && !msg.taskStatus && (
                <TaskConfirmCard
                  proposal={msg.proposal}
                  onConfirm={confirmTask(i, msg.proposal)}
                  onCancel={cancelTask(i, msg.proposal)}
                />
              )}
              {msg.role === "assistant" && msg.taskStatus === "confirmed" && (
                <div className="mt-2 text-xs text-emerald-600 flex items-center gap-1">
                  <span>✓</span> Task added to schedule
                </div>
              )}
              {msg.role === "assistant" && msg.taskStatus === "cancelled" && (
                <div className="mt-2 text-xs text-slate-400">Cancelled</div>
              )}
            </div>
          </div>
        ))}

        {/* Streaming response (in progress) */}
        {streaming && (
          <div className="flex gap-3">
            <div className="h-8 w-8 rounded-full bg-slate-900 shrink-0 flex items-center justify-center text-white text-xs font-bold">AI</div>
            <div className="max-w-[85%] bg-white border border-slate-200 rounded-2xl rounded-tl-sm px-4 py-3">
              {streamText ? (
                <span className="text-sm text-slate-700">
                  {renderContent(streamText)}
                  <span className="inline-block w-0.5 h-3.5 bg-slate-400 ml-0.5 animate-pulse align-middle" />
                </span>
              ) : (
                <div className="flex gap-1 items-center py-1">
                  {[0, 1, 2].map((i) => (
                    <div key={i} className="h-2 w-2 rounded-full bg-slate-300 animate-bounce"
                      style={{ animationDelay: `${i * 0.15}s` }} />
                  ))}
                </div>
              )}
            </div>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="bg-rose-50 border border-rose-100 rounded-xl px-4 py-3 text-xs text-rose-700">
            <span className="font-medium">Error: </span>{error}
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <div className="p-4 border-t border-slate-200 bg-white shrink-0">
        <form
          onSubmit={(e) => { e.preventDefault(); send(input); }}
          className="flex gap-2"
        >
          <input
            ref={inputRef}
            className="flex-1 bg-slate-100 rounded-xl px-4 py-3 outline-none text-sm border border-transparent focus:bg-white focus:border-slate-200"
            placeholder={streaming ? "Waiting for response…" : "Ask or schedule a task…"}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={streaming}
          />
          <button
            type="submit"
            disabled={streaming || !input.trim()}
            className="px-4 py-3 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-medium transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            {streaming ? (
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" className="animate-spin">
                <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"
                  stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              </svg>
            ) : "Send"}
          </button>
        </form>
        {messages.length > 0 && (
          <button
            onClick={() => void clearConversation()}
            className="mt-2 text-xs text-slate-400 hover:text-slate-600 transition-colors"
          >
            Clear conversation
          </button>
        )}
      </div>
    </div>
  );
}
