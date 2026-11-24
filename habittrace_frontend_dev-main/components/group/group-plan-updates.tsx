"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  getGroupPersonalReviews,
  type GroupPersonalContext,
  type GroupTask,
} from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";
import GroupPersonalPlan from "./group-personal-plan";

/** Private follow-up after any outcome write; shared completion remains an explicit action. */
export default function GroupPlanUpdates() {
  const [reviews, setReviews] = useState<GroupPersonalContext[]>([]);
  const [selected, setSelected] = useState<GroupTask | null>(null);
  const [error, setError] = useState(false);
  const generation = useRef({ sequence: 0 });
  const load = useCallback(async () => {
    const request = ++generation.current.sequence;
    try {
      const next = await getGroupPersonalReviews();
      if (request === generation.current.sequence) {
        setReviews(next);
        setError(false);
      }
    } catch {
      if (request === generation.current.sequence) setError(true);
    }
  }, []);
  useEffect(() => {
    const state = generation.current;
    const timer = setTimeout(() => void load(), 0);
    return () => {
      clearTimeout(timer);
      state.sequence++;
    };
  }, [load]);
  useDataRefresh(load);
  if (!reviews.length && !error && !selected) return null;
  return (
    <aside
      aria-label="Private group plan updates"
      className="mb-5 rounded-2xl border border-violet-200 bg-violet-50 p-4 text-sm"
    >
      <p className="font-semibold text-violet-950">Your linked group plans</p>
      {error && (
        <p className="mt-2">
          We couldn’t check group plan updates.{" "}
          <button
            type="button"
            className="underline"
            onClick={() => void load()}
          >
            Retry
          </button>
        </p>
      )}
      <ul className="mt-2 space-y-2">
        {reviews.map((review) => (
          <li key={review.group_task.id}>
            <button
              type="button"
              className="text-left text-violet-900 underline"
              onClick={() => setSelected(review.group_task)}
            >
              {review.group_task.title}:{" "}
              {review.blocks.some((b) => b.source_changed)
                ? "deadline or estimate needs review"
                : "personal work recorded — share completion?"}
            </button>
          </li>
        ))}
      </ul>
      {selected && (
        <GroupPersonalPlan
          task={selected}
          onClose={() => {
            setSelected(null);
            void load();
          }}
          onAdded={() => void load()}
        />
      )}
    </aside>
  );
}
