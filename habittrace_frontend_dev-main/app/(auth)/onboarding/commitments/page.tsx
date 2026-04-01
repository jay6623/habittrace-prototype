"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface Commitment {
  id: string;
  name: string;
  days: string;
  startTime: string;
  endTime: string;
}

export default function CommitmentsPage() {
  const router = useRouter();

  const [name, setName] = useState("");
  const [day, setDay] = useState("Monday");
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");

  const [commitments, setCommitments] = useState<Commitment[]>([
    { id: "1", name: "CS 4000 Lecture", days: "Mon / Wed / Fri", startTime: "9:00 AM", endTime: "10:15 AM" },
    { id: "2", name: "Work Shift", days: "Tue / Thu", startTime: "2:00 PM", endTime: "6:00 PM" },
  ]);

  function handleAdd() {
    if (!name || !startTime || !endTime) {
      alert("Please fill in all fields.");
      return;
    }

    const newCommitment: Commitment = {
      id: Date.now().toString(),
      name,
      days: day,
      startTime,
      endTime,
    };

    setCommitments([...commitments, newCommitment]);
    setName("");
    setStartTime("");
    setEndTime("");
  }

  function handleRemove(id: string) {
    setCommitments(commitments.filter((c) => c.id !== id));
  }

  function handleContinue() {
    // TODO: Save commitments to Supabase later
    console.log("Saving commitments:", commitments);
    router.push("/dashboard");
  }

  function handleBack() {
    router.push("/onboarding/profile");
  }

  return (
    <div className="max-w-4xl w-full">
      <div className="flex items-start justify-between gap-4 mb-6">
        <div>
          <div className="text-sm text-slate-500">Screen 4</div>
          <h1 className="text-3xl font-bold tracking-tight">Regular Commitments</h1>
          <p className="mt-2 text-sm text-slate-600">
            Add recurring classes, work shifts, and meetings so the scheduler can avoid conflicts.
          </p>
        </div>
        <span className="shrink-0 text-sm px-4 py-1.5 rounded-full border border-slate-200 bg-white font-medium">
          Step 2 of 2
        </span>
      </div>

      {/* Add form */}
      <div className="bg-white rounded-2xl border border-slate-200 p-5">
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium mb-2">Activity name</label>
            <input
              className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
              placeholder="CS 4000 Lecture"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-2">Day of week</label>
            <select
              className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none cursor-pointer"
              value={day}
              onChange={(e) => setDay(e.target.value)}
            >
              <option>Monday</option>
              <option>Tuesday</option>
              <option>Wednesday</option>
              <option>Thursday</option>
              <option>Friday</option>
              <option>Saturday</option>
              <option>Sunday</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium mb-2">Start time</label>
            <input
              className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
              placeholder="09:00 AM"
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-2">End time</label>
            <input
              className="w-full bg-slate-100 rounded-xl px-3 py-2.5 text-sm outline-none border border-transparent focus:bg-white focus:border-slate-200"
              placeholder="10:15 AM"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
            />
          </div>
        </div>

        <div className="mt-4 flex justify-end">
          <button
            onClick={handleAdd}
            className="px-4 py-2.5 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors"
          >
            Add commitment
          </button>
        </div>
      </div>

      {/* Saved items */}
      <div className="mt-5 bg-white rounded-2xl border border-slate-200 p-5">
        <div className="font-semibold text-sm">Saved recurring items</div>
        <div className="text-sm text-slate-500">These commitments will block unavailable time slots.</div>

        <div className="mt-4 grid sm:grid-cols-2 gap-3">
          {commitments.map((item) => (
            <div key={item.id} className="rounded-xl border border-slate-200 p-4 flex items-start justify-between">
              <div>
                <div className="font-medium text-sm">{item.name}</div>
                <div className="text-xs text-slate-500 mt-1">
                  {item.days} • {item.startTime} – {item.endTime}
                </div>
              </div>
              <button
                onClick={() => handleRemove(item.id)}
                className="text-slate-400 hover:text-rose-500 text-sm ml-3"
              >
                ✕
              </button>
            </div>
          ))}
        </div>

        {commitments.length === 0 && (
          <div className="mt-4 text-sm text-slate-400 text-center py-6">
            No commitments added yet.
          </div>
        )}
      </div>

      {/* Navigation */}
      <div className="mt-5 flex justify-end gap-3">
        <button
          onClick={handleBack}
          className="px-5 py-2.5 rounded-xl bg-slate-100 text-sm font-medium hover:bg-slate-200 transition-colors"
        >
          Back
        </button>
        <button
          onClick={handleContinue}
          className="px-5 py-2.5 rounded-xl bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 transition-colors"
        >
          Continue to Dashboard
        </button>
      </div>
    </div>
  );
}