"use client";

import { useCallback, useEffect, useState } from "react";
import { getPersonalizedOutlook, type PersonalizedOutlook } from "@/lib/api";
import { useDataRefresh } from "@/lib/refresh";

function percent(value: number | null | undefined) {
  return `${Math.round((value ?? 0) * 100)}%`;
}

export default function PersonalizedOutlookCard() {
  const [outlook, setOutlook] = useState<PersonalizedOutlook | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(async () => {
    try {
      setOutlook(await getPersonalizedOutlook());
      setFailed(false);
    } catch {
      setFailed(true);
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);
  useDataRefresh(load);

  return (
    <section className="overflow-hidden rounded-3xl border border-emerald-100 bg-gradient-to-br from-emerald-50 via-white to-lime-50 shadow-sm">
      <div className="flex items-start justify-between gap-4 p-5">
        <div>
          <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-emerald-700">
            Personalized outlook · Experimental
          </p>
          <h2 className="mt-1 text-xl font-bold tracking-tight text-slate-950">
            Today&apos;s planning outlook
          </h2>
        </div>
        {outlook?.available && outlook.predicted_success_probability !== null ? (
          <div className="shrink-0 rounded-xl bg-emerald-700 px-3 py-2 text-right text-white">
            <p className="text-2xl font-black tabular-nums">
              {percent(outlook.predicted_success_probability)}
            </p>
            <p className="text-[10px] font-semibold text-emerald-100">estimated</p>
          </div>
        ) : null}
      </div>

      {outlook?.available ? (
        <div className="space-y-2 px-5 pb-5">
          <div className="rounded-xl bg-white/85 p-3 ring-1 ring-emerald-100">
            <p className="text-[10px] font-bold uppercase tracking-wide text-emerald-700">
              Strongest plan
            </p>
            <p className="mt-1 truncate text-sm font-bold text-slate-900">
              {outlook.highest_potential?.title}
            </p>
            <p className="mt-0.5 text-xs text-slate-500">
              {percent(outlook.highest_potential?.success_probability)} estimated
            </p>
          </div>
          <div className="rounded-xl bg-amber-50/90 p-3 ring-1 ring-amber-100">
            <p className="text-[10px] font-bold uppercase tracking-wide text-amber-700">
              Needs attention
            </p>
            <p className="mt-1 truncate text-sm font-bold text-slate-900">
              {outlook.needs_attention?.title}
            </p>
            <p className="mt-0.5 text-xs text-slate-600">
              {outlook.needs_attention?.predicted_failure_reason
                ? `Risk: ${outlook.needs_attention.predicted_failure_reason.replaceAll("_", " ")}`
                : `${percent(outlook.needs_attention?.success_probability)} estimated`}
            </p>
          </div>
          <div className="pt-2">
            <p className="text-xs font-bold text-emerald-800">One thing to try</p>
            <p className="mt-1 text-sm font-bold text-slate-900">
              {outlook.recommendation?.title ?? "Keep the plan specific"}
            </p>
            <p className="mt-1 text-xs leading-5 text-slate-600">
              {outlook.recommendation?.detail ??
                "Define one small action before you begin."}
            </p>
          </div>
        </div>
      ) : (
        <div className="px-5 pb-5 text-sm leading-6 text-slate-600">
          {failed || outlook?.reason === "model_unavailable"
            ? "AI planning guidance is temporarily unavailable. Your plans still work normally."
            : outlook?.reason === "no_pending_plans"
              ? "There are no pending plans to assess today."
              : "Checking today’s plans…"}
        </div>
      )}

      <div className="border-t border-emerald-100 bg-white/60 px-5 py-2.5 text-[11px] leading-4 text-slate-500">
        {outlook?.personalization.applied
          ? `${outlook.personalization.sample_count} recorded outcomes used · ${Math.round(outlook.personalization.confidence * 100)}% personalization confidence`
          : "Personalization improves as you record more outcomes."}
      </div>
    </section>
  );
}
