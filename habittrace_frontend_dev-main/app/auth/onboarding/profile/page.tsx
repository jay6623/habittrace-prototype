"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

// ── Types ──────────────────────────────────────────────
type WorkingTime = "morning" | "afternoon" | "night";
type FocusDuration = "25" | "45" | "60" | "90";
type Flexibility = "very-fixed" | "somewhat-flexible" | "very-flexible";
type DistractionLevel = "low" | "medium" | "high";

// ── Preview messages based on selections ───────────────
function getPreviewMessage(
  workingTime: WorkingTime,
  focusDuration: FocusDuration
): string {
  const timeLabel: Record<WorkingTime, string> = {
    morning: "morning",
    afternoon: "afternoon",
    night: "evening",
  };

  return `HabitTrace will prioritize ${timeLabel[workingTime]} focus blocks of ~${focusDuration} minutes and recommend realistic durations.`;
}

// ── Component ──────────────────────────────────────────
export default function ProfileSetupPage() {
  const router = useRouter();

  const [workingTime, setWorkingTime] = useState<WorkingTime>("night");
  const [focusDuration, setFocusDuration] = useState<FocusDuration>("60");
  const [flexibility, setFlexibility] = useState<Flexibility>("somewhat-flexible");
  const [distraction, setDistraction] = useState<DistractionLevel>("medium");

  function handleSave() {
    // TODO: Save to Supabase user_preferences table later
    const preferences = { workingTime, focusDuration, flexibility, distraction };
    console.log("Saving preferences:", preferences);

    // Go to step 2 (commitments page)
    router.push("/onboarding/commitments");
  }

  function handleSkip() {
    router.push("/onboarding/commitments");
  }

  return (
    <div className="max-w-5xl w-full">
      {/* Header */}
      <div className="flex items-start justify-between gap-4 mb-6">
        <div>
          <div className="text-sm text-slate-500">Screen 3</div>
          <h1 className="text-3xl font-bold tracking-tight">
            Productivity Profile Setup
          </h1>
          <p className="mt-2 text-sm text-slate-600 max-w-xl">
            First-time users answer a few questions so HabitTrace can personalize
            scheduling suggestions.
          </p>
        </div>
        <span className="shrink-0 text-sm px-4 py-1.5 rounded-full border border-slate-200 bg-white font-medium">
          Step 1 of 2
        </span>
      </div>

      {/* Question Cards */}
      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Q1 — Preferred working time */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="text-xs text-slate-500">Question 1</div>
          <div className="font-semibold mt-1 text-sm">Preferred working time</div>
          <div className="mt-4 space-y-2">
            {(["morning", "afternoon", "night"] as WorkingTime[]).map((time) => (
              <button
                key={time}
                onClick={() => setWorkingTime(time)}
                className={`w-full rounded-xl py-2.5 text-sm font-medium transition-colors ${
                  workingTime === time
                    ? "bg-slate-900 text-white"
                    : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                }`}
              >
                {time.charAt(0).toUpperCase() + time.slice(1)}
              </button>
            ))}
          </div>
        </div>

        {/* Q2 — Typical focus duration */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="text-xs text-slate-500">Question 2</div>
          <div className="font-semibold mt-1 text-sm">Typical focus duration</div>
          <select
            value={focusDuration}
            onChange={(e) => setFocusDuration(e.target.value as FocusDuration)}
            className="mt-4 w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:border-slate-300 focus:bg-white transition-colors cursor-pointer"
          >
            <option value="25">25 minutes</option>
            <option value="45">45 minutes</option>
            <option value="60">60 minutes</option>
            <option value="90">90 minutes</option>
          </select>
        </div>

        {/* Q3 — Schedule flexibility */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="text-xs text-slate-500">Question 3</div>
          <div className="font-semibold mt-1 text-sm">Schedule flexibility</div>
          <select
            value={flexibility}
            onChange={(e) => setFlexibility(e.target.value as Flexibility)}
            className="mt-4 w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:border-slate-300 focus:bg-white transition-colors cursor-pointer"
          >
            <option value="very-fixed">Very fixed</option>
            <option value="somewhat-flexible">Somewhat flexible</option>
            <option value="very-flexible">Very flexible</option>
          </select>
        </div>

        {/* Q4 — Distraction level */}
        <div className="bg-white rounded-2xl border border-slate-200 p-5">
          <div className="text-xs text-slate-500">Question 4</div>
          <div className="font-semibold mt-1 text-sm">Distraction level</div>
          <select
            value={distraction}
            onChange={(e) => setDistraction(e.target.value as DistractionLevel)}
            className="mt-4 w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:border-slate-300 focus:bg-white transition-colors cursor-pointer"
          >
            <option value="low">Low</option>
            <option value="medium">Medium</option>
            <option value="high">High</option>
          </select>
        </div>
      </div>

      {/* Personalization Preview */}
      <div className="mt-5 bg-white rounded-2xl border border-slate-200 p-5 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <div className="font-semibold text-sm">Personalization preview</div>
          <div className="text-sm text-slate-500 mt-1">
            {getPreviewMessage(workingTime, focusDuration)}
          </div>
        </div>
        <div className="flex gap-3 shrink-0">
          <button
            onClick={handleSkip}
            className="px-5 py-2.5 rounded-xl bg-slate-100 hover:bg-slate-200 text-sm font-medium transition-colors"
          >
            Skip for now
          </button>
          <button
            onClick={handleSave}
            className="px-5 py-2.5 rounded-xl bg-slate-900 text-white hover:bg-slate-800 text-sm font-semibold transition-colors"
          >
            Save profile
          </button>
        </div>
      </div>
    </div>
  );
}