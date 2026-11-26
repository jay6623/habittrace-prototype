"use client";
import { useCallback, useEffect, useState, useRef } from "react";
import {
  setProjectTimezone,
  editProjectMilestone,
  removeProjectMilestone,
  getProjectForecast,
  setProjectDependency,
  createProjectMilestone,
  confirmProjectMilestone,
  shareProjectCapacity,
  shareRemainingWork,
  requestProjectHelp,
  replyProjectHelp,
  type ProjectForecast,
  type GroupTask,
} from "@/lib/api";
import { describeApiError } from "@/lib/group";
import { useDataRefresh } from "@/lib/refresh";
import { localDateString } from "@/lib/mobile-task";
const input =
  "min-h-11 w-full rounded-xl border border-slate-200 bg-white px-3 text-sm";
const badges: Record<string, string> = {
  complete: "bg-emerald-100 text-emerald-900",
  review: "bg-violet-100 text-violet-900",
  on_track: "bg-emerald-50 text-emerald-800",
  at_risk: "bg-rose-100 text-rose-900",
  unknown: "bg-slate-100 text-slate-700",
  blocked: "bg-amber-100 text-amber-900",
  scheduled: "bg-sky-50 text-sky-800",
};
const names: Record<string, string> = {
  complete: "Complete",
  review: "Ready for review",
  on_track: "Fits the estimate",
  at_risk: "Needs attention",
  unknown: "Needs more information",
  blocked: "Waiting on another task",
  scheduled: "Fits shared availability",
};
export default function ProjectForecastPanel({
  groupId,
  userId,
  tasks,
  isAdmin,
}: {
  groupId: string;
  userId: string;
  tasks: GroupTask[];
  isAdmin: boolean;
}) {
  const [data, setData] = useState<ProjectForecast | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [task, setTask] = useState("");
  const [predecessor, setPredecessor] = useState("");
  const milestoneForm = useRef<HTMLDetailsElement>(null);
  const [editingMilestone, setEditingMilestone] = useState<string | null>(null);
  const [milestoneZone, setMilestoneZone] = useState("");
  const [milestone, setMilestone] = useState("");
  const [due, setDue] = useState("");
  const [criteria, setCriteria] = useState("");
  const [milestoneTasks, setMilestoneTasks] = useState<string[]>([]);
  const [projectTimezone, setProjectTimezoneDraft] = useState("");
  const [capacity, setCapacity] = useState("");
  const [until, setUntil] = useState("");
  const [myTask, setMyTask] = useState("");
  const [remaining, setRemaining] = useState("");
  const [helpTask, setHelpTask] = useState("");
  const [helper, setHelper] = useState("");
  const [helpMessage, setHelpMessage] = useState("");
  const load = useCallback(async () => {
    try {
      const next = await getProjectForecast(groupId);
      setData(next);
      setError(null);
    } catch (e) {
      setError(
        describeApiError(
          e,
          "We couldn't load project estimates. Your tasks have not changed.",
        ),
      );
    }
  }, [groupId]);
  useEffect(() => {
    let active = true;
    getProjectForecast(groupId)
      .then((d) => {
        if (active) setData(d);
      })
      .catch((e) => {
        if (active)
          setError(
            describeApiError(
              e,
              "Project estimates are unavailable. Your shared tasks still work.",
            ),
          );
      });
    return () => {
      active = false;
    };
  }, [groupId]);
  useDataRefresh(load);
  async function act(work: () => Promise<unknown>, success: string) {
    if (busy) return;
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await work();
      setMessage(success);
      await load();
    } catch (e) {
      setError(
        describeApiError(
          e,
          "We couldn't save this change. Your inputs are still here.",
        ),
      );
    } finally {
      setBusy(false);
    }
  }
  async function saveMilestone(value: {
    title: string;
    due_date: string;
    completion_criteria: string;
    task_ids: string[];
    timezone_name: string;
  }) {
    const result = await (editingMilestone
      ? editProjectMilestone(groupId, editingMilestone, {
          ...value,
          timezone_name: milestoneZone || value.timezone_name,
        })
      : createProjectMilestone(groupId, value));
    setEditingMilestone(null);
    setMilestone("");
    setDue("");
    setCriteria("");
    setMilestoneTasks([]);
    if (milestoneForm.current) milestoneForm.current.open = false;
    return result;
  }
  const own = tasks.filter((t) => t.assigned_to_ids.includes(userId));
  const name = (id: string) =>
    data?.workload.find((m) => m.user_id === id)?.name || "Member";
  const title = (id: string) =>
    tasks.find((t) => t.id === id)?.title || "Removed task";
  const choices = (items: GroupTask[]) =>
    items.map((t) => (
      <option key={t.id} value={t.id}>
        {t.title}
      </option>
    ));
  if (!data && !error)
    return (
      <div
        className="rounded-2xl border border-slate-200 bg-white p-8 text-sm"
        role="status"
      >
        Checking project flow…
      </div>
    );
  const attention =
    data?.tasks.filter((t) => t.status === "at_risk").length || 0;
  const blocked = data?.tasks.filter((t) => t.status === "blocked").length || 0;
  const unknown = data?.tasks.filter((t) => t.status === "unknown").length || 0;
  return (
    <div className="space-y-5">
      <section className="rounded-2xl border border-violet-200 bg-gradient-to-br from-violet-50 to-white p-5 sm:p-6">
        <p className="text-xs font-semibold uppercase tracking-wide text-violet-700">
          Project outlook
        </p>
        <h2 className="mt-1 text-xl font-bold">
          See what needs attention before the deadline
        </h2>
        <p className="mt-2 max-w-2xl text-sm text-slate-600">
          Connect tasks, set checkpoints and share only the availability you
          choose. We explain schedule risks without rating teammates.
        </p>
        <div className="mt-5 grid grid-cols-3 gap-2">
          {[
            {
              value: attention,
              label: "Need attention",
              tone: "text-rose-700",
            },
            {
              value: blocked,
              label: "Waiting on work",
              tone: "text-amber-800",
            },
            {
              value: unknown,
              label: "Need information",
              tone: "text-slate-600",
            },
          ].map((x) => (
            <div key={x.label} className="rounded-xl bg-white p-3">
              <p className={`text-2xl font-bold ${x.tone}`}>{x.value}</p>
              <p className="text-xs text-slate-500">{x.label}</p>
            </div>
          ))}
        </div>
        <p className="mt-3 text-xs text-slate-500">
          Schedule estimates from shared information, not a team success
          probability. Dates are shown in{" "}
          {data?.timezone_name || "your timezone"}.
        </p>
      </section>
      {error && (
        <div
          role="alert"
          className="rounded-xl bg-rose-50 p-4 text-sm text-rose-800"
        >
          {error}{" "}
          <button className="underline" onClick={() => void load()}>
            Retry
          </button>
        </div>
      )}
      {message && (
        <p
          role="status"
          className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-900"
        >
          {message}
        </p>
      )}
      {data && (
        <>
          {isAdmin && (
            <details className="rounded-xl border border-slate-200 bg-white p-4">
              <summary className="cursor-pointer text-sm font-medium">
                Project time reference: {data.timezone_name}
              </summary>
              <form
                className="mt-3 flex flex-wrap gap-2"
                onSubmit={(e) => {
                  e.preventDefault();
                  void act(
                    () => setProjectTimezone(groupId, projectTimezone),
                    "Project time reference updated.",
                  );
                }}
              >
                <label className="flex-1 text-sm">
                  Shared timezone (IANA name)
                  <input
                    className={input}
                    required
                    value={projectTimezone}
                    placeholder="America/Denver"
                    disabled={busy}
                    onChange={(e) => setProjectTimezoneDraft(e.target.value)}
                  />
                </label>
                <button className="btn-secondary self-end" disabled={busy}>
                  Save timezone
                </button>
              </form>
              <p className="mt-2 text-xs text-slate-500">
                Daily availability is interpreted in this shared timezone for
                every teammate. Milestones keep the timezone captured when
                created.
              </p>
            </details>
          )}
          <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 className="font-semibold">1. Map the work</h3>
                <p className="mt-1 text-sm text-slate-500">
                  A predecessor must finish before the next task can start.
                </p>
              </div>
            </div>
            {data.dependencies.length ? (
              <ul className="my-4 space-y-2">
                {data.dependencies.map((edge) => (
                  <li
                    key={edge.task_id + edge.predecessor_id}
                    className="flex items-center justify-between gap-2 rounded-xl bg-slate-50 p-3 text-sm"
                  >
                    <span>
                      {title(edge.predecessor_id)}{" "}
                      <span aria-label="then" className="px-2 text-violet-600">
                        →
                      </span>{" "}
                      {title(edge.task_id)}
                    </span>
                    <button
                      aria-label={`Remove dependency from ${title(edge.predecessor_id)} to ${title(edge.task_id)}`}
                      className="text-slate-500 underline"
                      disabled={busy}
                      onClick={() =>
                        void act(
                          () =>
                            setProjectDependency(
                              groupId,
                              edge.task_id,
                              edge.predecessor_id,
                              true,
                            ),
                          "Dependency removed.",
                        )
                      }
                    >
                      Remove
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="my-4 rounded-xl bg-slate-50 p-3 text-sm text-slate-500">
                No connections yet. Start with “Research → Draft → Review”. Add
                review work as a task so time is reserved for it.
              </p>
            )}
            <form
              className="grid gap-3 sm:grid-cols-[1fr_1fr_auto]"
              onSubmit={(e) => {
                e.preventDefault();
                void act(
                  () => setProjectDependency(groupId, task, predecessor),
                  "Task connection saved.",
                );
              }}
            >
              <label className="text-xs font-medium">
                This task
                <select
                  className={`${input} mt-1`}
                  required
                  value={task}
                  disabled={busy}
                  onChange={(e) => setTask(e.target.value)}
                >
                  <option value="">Choose task</option>
                  {choices(tasks)}
                </select>
              </label>
              <label className="text-xs font-medium">
                Waits for
                <select
                  className={`${input} mt-1`}
                  required
                  value={predecessor}
                  disabled={busy}
                  onChange={(e) => setPredecessor(e.target.value)}
                >
                  <option value="">Choose predecessor</option>
                  {choices(tasks.filter((t) => t.id !== task))}
                </select>
              </label>
              <button
                className="btn-secondary self-end"
                disabled={busy || tasks.length < 2}
              >
                Connect
              </button>
            </form>
          </section>
          <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <h3 className="font-semibold">2. Check milestones</h3>
            <p className="mt-1 text-sm text-slate-500">
              Define what “done” means. Linked tasks must finish before an owner
              or admin confirms the milestone.
            </p>
            <div className="my-4 grid gap-3 sm:grid-cols-2">
              {data.milestones.map((m) => (
                <article
                  key={m.id}
                  className="rounded-xl border border-slate-200 p-4"
                >
                  <div className="flex flex-wrap justify-between gap-2">
                    <h4 className="font-semibold">{m.title}</h4>
                    <span
                      className={`rounded-full px-2 py-1 text-xs ${badges[m.status]}`}
                    >
                      {names[m.status]}
                    </span>
                  </div>
                  <p className="mt-2 text-sm">Due {m.due_date}</p>
                  <p className="mt-1 text-sm text-slate-600">
                    Done means: {m.completion_criteria}
                  </p>
                  <p className="mt-2 text-xs text-slate-500">
                    {m.task_ids.map(title).join(" → ")}
                  </p>
                  {m.forecast_finish && (
                    <p className="mt-2 text-sm">
                      Estimated finish:{" "}
                      {new Date(m.forecast_finish).toLocaleString()}
                      {m.slack_minutes !== null
                        ? ` · ${Math.abs(Math.round(m.slack_minutes / 60))}h ${m.slack_minutes < 0 ? "past deadline" : "of slack"}`
                        : ""}
                    </p>
                  )}
                  {m.missing_task_ids.length > 0 && (
                    <p className="mt-2 text-sm text-amber-800">
                      A linked task was removed. Recreate this milestone with
                      current tasks.
                    </p>
                  )}
                  <div className="mt-3 flex flex-wrap gap-3 text-xs">
                    <button
                      type="button"
                      className="text-violet-700 underline"
                      disabled={busy}
                      onClick={() => {
                        setEditingMilestone(m.id);
                        setMilestone(m.title);
                        setDue(m.due_date);
                        setCriteria(m.completion_criteria);
                        setMilestoneTasks(m.task_ids);
                        setMilestoneZone(m.timezone_name || "UTC");
                        if (milestoneForm.current) {
                          milestoneForm.current.open = true;
                          milestoneForm.current.scrollIntoView({
                            block: "center",
                            behavior: "smooth",
                          });
                        }
                      }}
                    >
                      Edit checkpoint
                    </button>
                    <button
                      type="button"
                      className="text-slate-500 underline"
                      disabled={busy}
                      onClick={() => {
                        if (
                          window.confirm(
                            "Remove this milestone? Its tasks and results will stay.",
                          )
                        )
                          void act(
                            () => removeProjectMilestone(groupId, m.id),
                            "Milestone removed. Tasks and results were preserved.",
                          );
                      }}
                    >
                      Remove milestone
                    </button>
                  </div>
                  {m.status === "review" && isAdmin && (
                    <button
                      className="btn-secondary mt-3"
                      disabled={busy}
                      onClick={() =>
                        void act(
                          () => confirmProjectMilestone(groupId, m.id),
                          "Milestone criteria confirmed.",
                        )
                      }
                    >
                      Confirm criteria are met
                    </button>
                  )}
                </article>
              ))}
            </div>
            <details ref={milestoneForm} className="rounded-xl bg-slate-50 p-4">
              <summary className="cursor-pointer text-sm font-medium">
                {editingMilestone ? "Edit milestone" : "+ Add a milestone"}
              </summary>
              <form
                className="mt-4 space-y-3"
                onSubmit={(e) => {
                  e.preventDefault();
                  void act(
                    () =>
                      saveMilestone({
                        title: milestone,
                        due_date: due,
                        completion_criteria: criteria,
                        timezone_name:
                          Intl.DateTimeFormat().resolvedOptions().timeZone ||
                          "UTC",
                        task_ids: milestoneTasks,
                      }),
                    "Milestone saved.",
                  );
                }}
              >
                <label className="block text-sm">
                  Milestone name
                  <input
                    className={`${input} mt-1`}
                    required
                    maxLength={120}
                    value={milestone}
                    disabled={busy}
                    onChange={(e) => setMilestone(e.target.value)}
                    placeholder="First draft ready"
                  />
                </label>
                <label className="block text-sm">
                  Due date
                  <input
                    className={`${input} mt-1`}
                    required
                    type="date"
                    value={due}
                    disabled={busy}
                    onChange={(e) => setDue(e.target.value)}
                  />
                </label>
                <label className="block text-sm">
                  What must be true to call it done?
                  <input
                    className={`${input} mt-1`}
                    required
                    maxLength={500}
                    value={criteria}
                    disabled={busy}
                    onChange={(e) => setCriteria(e.target.value)}
                    placeholder="Draft includes every section and is ready for team review"
                  />
                </label>
                <fieldset disabled={busy}>
                  <legend className="text-sm">Tasks included</legend>
                  <div className="mt-2 grid gap-2 sm:grid-cols-2">
                    {tasks.map((t) => (
                      <label
                        key={t.id}
                        className="flex items-center gap-2 text-sm"
                      >
                        <input
                          type="checkbox"
                          checked={milestoneTasks.includes(t.id)}
                          onChange={(e) =>
                            setMilestoneTasks((current) =>
                              e.target.checked
                                ? [...current, t.id]
                                : current.filter((id) => id !== t.id),
                            )
                          }
                        />
                        {t.title}
                      </label>
                    ))}
                  </div>
                </fieldset>
                <button
                  className="btn-primary"
                  disabled={busy || !milestoneTasks.length}
                >
                  {editingMilestone
                    ? "Save milestone changes"
                    : "Create milestone"}
                </button>
                {editingMilestone && (
                  <button
                    className="btn-secondary ml-2"
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      setEditingMilestone(null);
                      setMilestone("");
                      setDue("");
                      setCriteria("");
                      setMilestoneTasks([]);
                    }}
                  >
                    Cancel editing
                  </button>
                )}
              </form>
            </details>
          </section>
          <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <h3 className="font-semibold">3. Find bottlenecks & next steps</h3>
            <div className="mt-4 space-y-3">
              {[...data.tasks]
                .sort((a, b) => b.downstream_count - a.downstream_count)
                .map((item) => (
                  <article
                    key={item.task_id}
                    className="rounded-xl border border-slate-200 p-4"
                  >
                    <div className="flex flex-wrap justify-between gap-2">
                      <h4 className="font-medium">{item.title}</h4>
                      <span
                        className={`rounded-full px-2 py-1 text-xs ${badges[item.status]}`}
                      >
                        {names[item.status]}
                      </span>
                    </div>
                    {item.downstream_count > 0 && (
                      <p className="mt-1 text-xs font-medium text-violet-700">
                        {item.downstream_count} unfinished downstream task
                        {item.downstream_count > 1 ? "s" : ""} depend on this
                      </p>
                    )}
                    <p className="mt-2 text-sm text-slate-600">
                      {item.remaining_minutes === null
                        ? "Remaining work not known"
                        : `${item.remaining_minutes} min remaining across assignees`}
                      {item.forecast_finish && item.status !== "complete"
                        ? ` · estimated finish ${new Date(item.forecast_finish).toLocaleString()}`
                        : ""}
                    </p>
                    <ul className="mt-2 space-y-1 text-sm text-slate-600">
                      {item.reasons.map((reason) => (
                        <li key={reason}>• {reason}</li>
                      ))}
                    </ul>
                    {data.suggestions.find((s) => s.task_id === item.task_id)
                      ?.helper_ids.length ? (
                      <p className="mt-2 text-xs text-violet-800">
                        Shared availability suggests asking{" "}
                        {data.suggestions
                          .find((s) => s.task_id === item.task_id)!
                          .helper_ids.map(name)
                          .join(" or ")}
                        . Confirm scope with them first.
                      </p>
                    ) : null}
                  </article>
                ))}
            </div>
          </section>
          <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <h3 className="font-semibold">Share only what your team needs</h3>
            <p className="mt-1 text-sm text-slate-500">
              Your calendar, energy, focus and personal scores stay private.
              These fields are optional and visible to this group.
            </p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {data.workload.map((m) => (
                <div
                  key={m.user_id}
                  className="rounded-xl bg-slate-50 p-3 text-sm"
                >
                  <p className="font-medium">
                    {m.name}
                    {m.user_id === userId ? " (you)" : ""}
                  </p>
                  <p className="mt-1">
                    {m.minutes_per_day === null
                      ? "Availability not shared"
                      : `${m.minutes_per_day} min/day through ${m.available_until}`}
                  </p>
                  <p className="text-xs text-slate-500">
                    {m.remaining_minutes} min known work
                    {m.has_unknown_work ? " + some unknown work" : ""}
                  </p>
                </div>
              ))}
            </div>
            <details className="mt-4 rounded-xl border border-slate-200 p-4">
              <summary className="cursor-pointer text-sm font-medium">
                Manage my shared availability & remaining work
              </summary>
              <form
                className="mt-4 space-y-3"
                onSubmit={(e) => {
                  e.preventDefault();
                  void act(
                    () =>
                      shareProjectCapacity(groupId, Number(capacity), until),
                    "Your availability is now shared with this group.",
                  );
                }}
              >
                <div className="grid grid-cols-1 min-[400px]:grid-cols-2 gap-3">
                  <label className="text-sm">
                    Minutes per day
                    <input
                      className={`${input} mt-1`}
                      type="number"
                      required
                      min={0}
                      max={720}
                      value={capacity}
                      disabled={busy}
                      onChange={(e) => setCapacity(e.target.value)}
                    />
                  </label>
                  <label className="text-sm">
                    Share through
                    <input
                      className={`${input} mt-1`}
                      type="date"
                      required
                      min={localDateString()}
                      value={until}
                      disabled={busy}
                      onChange={(e) => setUntil(e.target.value)}
                    />
                  </label>
                </div>
                <div className="flex flex-wrap gap-2">
                  <button className="btn-secondary" disabled={busy}>
                    Share these minutes
                  </button>
                  <button
                    className="btn-secondary"
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void act(
                        () => shareProjectCapacity(groupId, null, null),
                        "Your availability is no longer shared.",
                      )
                    }
                  >
                    Stop sharing availability
                  </button>
                </div>
              </form>
              <form
                className="mt-5 space-y-3 border-t border-slate-200 pt-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  void act(
                    () =>
                      shareRemainingWork(groupId, myTask, Number(remaining)),
                    "Your remaining work estimate is now shared.",
                  );
                }}
              >
                <label className="block text-sm">
                  My assigned task
                  <select
                    className={`${input} mt-1`}
                    required
                    value={myTask}
                    disabled={busy}
                    onChange={(e) => setMyTask(e.target.value)}
                  >
                    <option value="">Choose task</option>
                    {choices(own)}
                  </select>
                </label>
                <label className="block text-sm">
                  My estimated minutes still needed
                  <input
                    className={`${input} mt-1`}
                    required
                    type="number"
                    min={0}
                    max={10080}
                    value={remaining}
                    disabled={busy}
                    onChange={(e) => setRemaining(e.target.value)}
                  />
                </label>
                <p className="text-xs text-slate-500">
                  0 means no more work estimated; it does not mark completion.
                  This does not reveal your personal progress records.
                </p>
                <div className="flex flex-wrap gap-2">
                  <button className="btn-secondary" disabled={busy}>
                    Share remaining estimate
                  </button>
                  <button
                    className="btn-secondary"
                    type="button"
                    disabled={busy || !myTask}
                    onClick={() =>
                      void act(
                        () => shareRemainingWork(groupId, myTask, null),
                        "Remaining estimate cleared; the shared task estimate is used instead.",
                      )
                    }
                  >
                    Clear my estimate
                  </button>
                </div>
              </form>
            </details>
          </section>
          <section className="rounded-2xl border border-slate-200 bg-white p-5">
            <h3 className="font-semibold">Ask for a small handoff</h3>
            <p className="mt-1 text-sm text-slate-500">
              Requests and replies are visible to this group. Accepting records
              an agreement; it never changes assignments automatically.
            </p>
            <ul className="my-4 space-y-2">
              {data.help_requests.map((r) => (
                <li key={r.id} className="rounded-xl bg-slate-50 p-3 text-sm">
                  <p className="font-medium">
                    {name(r.requester_id)} → {name(r.helper_id)} ·{" "}
                    {title(r.task_id)}
                  </p>
                  <p className="mt-1">{r.message}</p>
                  <p className="mt-1 text-xs capitalize text-slate-500">
                    {r.status}
                  </p>
                  {r.helper_id === userId && r.status === "pending" && (
                    <div className="mt-2 flex gap-2">
                      <button
                        className="btn-secondary"
                        disabled={busy}
                        onClick={() =>
                          void act(
                            () => replyProjectHelp(groupId, r.id, "accepted"),
                            "Agreement recorded. Discuss the scope before changing assignments.",
                          )
                        }
                      >
                        Accept discussion
                      </button>
                      <button
                        className="btn-secondary"
                        disabled={busy}
                        onClick={() =>
                          void act(
                            () => replyProjectHelp(groupId, r.id, "declined"),
                            "Request declined.",
                          )
                        }
                      >
                        Decline
                      </button>
                    </div>
                  )}
                </li>
              ))}
            </ul>
            <details className="rounded-xl border border-slate-200 p-4">
              <summary className="cursor-pointer text-sm font-medium">
                + Request help
              </summary>
              <form
                className="mt-3 space-y-3"
                onSubmit={(e) => {
                  e.preventDefault();
                  void act(
                    () =>
                      requestProjectHelp(
                        groupId,
                        helpTask,
                        helper,
                        helpMessage,
                      ),
                    "Help request shared with your group.",
                  );
                }}
              >
                <label className="block text-sm">
                  My task
                  <select
                    className={`${input} mt-1`}
                    required
                    disabled={busy}
                    value={helpTask}
                    onChange={(e) => setHelpTask(e.target.value)}
                  >
                    <option value="">Choose task</option>
                    {choices(own)}
                  </select>
                </label>
                <label className="block text-sm">
                  Ask a teammate
                  <select
                    className={`${input} mt-1`}
                    required
                    disabled={busy}
                    value={helper}
                    onChange={(e) => setHelper(e.target.value)}
                  >
                    <option value="">Choose teammate</option>
                    {data.workload
                      .filter((m) => m.user_id !== userId)
                      .map((m) => (
                        <option value={m.user_id} key={m.user_id}>
                          {m.name}
                        </option>
                      ))}
                  </select>
                </label>
                <label className="block text-sm">
                  A small, specific part they could help with
                  <textarea
                    className={`${input} mt-1 py-2`}
                    required
                    maxLength={300}
                    disabled={busy}
                    value={helpMessage}
                    onChange={(e) => setHelpMessage(e.target.value)}
                    placeholder="Could you review the introduction tomorrow?"
                  />
                </label>
                <button className="btn-primary" disabled={busy}>
                  Share help request
                </button>
              </form>
            </details>
          </section>
          <details className="rounded-xl bg-slate-100 p-4 text-xs text-slate-600">
            <summary className="cursor-pointer font-medium">
              How to read these estimates
            </summary>
            <ul className="mt-2 space-y-2">
              {data.assumptions.map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
            <p className="mt-2">
              Last calculated {new Date(data.generated_at).toLocaleString()}.
              Shared availability does not include private calendar conflicts.
            </p>
          </details>
        </>
      )}
    </div>
  );
}
