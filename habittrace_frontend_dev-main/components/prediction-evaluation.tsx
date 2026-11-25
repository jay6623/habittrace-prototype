"use client";
import { useEffect, useState } from "react";
import { getPredictionEvaluation, type PredictionEvaluation } from "@/lib/api";
export default function PredictionEvaluationCard() {
  const [data, setData] = useState<PredictionEvaluation | null>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    let active = true;
    getPredictionEvaluation()
      .then((d) => {
        if (active) setData(d);
      })
      .catch(() => {
        if (active) setError(true);
      });
    return () => {
      active = false;
    };
  }, []);
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5">
      <h2 className="font-semibold">Are my estimates getting closer?</h2>
      <p className="mt-1 text-sm text-slate-500">
        We compare estimates made before work with results from the exact plan
        you selected.
      </p>
      {error ? (
        <p className="mt-3 text-sm text-amber-800">
          Estimate evaluation is unavailable. Your plans and results are safe.
        </p>
      ) : !data ? (
        <p className="mt-3 text-sm">Loading evaluation…</p>
      ) : (
        <>
          <div className="my-4 grid grid-cols-3 gap-3">
            {[
              { label: "Comparisons viewed", value: data.shown },
              { label: "Choices applied", value: data.selected },
              { label: "Results matched", value: data.evaluated.count },
            ].map((x) => (
              <div key={x.label} className="rounded-xl bg-slate-50 p-3">
                <p className="text-xl font-semibold">{x.value}</p>
                <p className="text-xs text-slate-500">{x.label}</p>
              </div>
            ))}
          </div>
          {data.evaluated.count < 5 ? (
            <p className="text-sm text-slate-600">
              Too few matched results to judge quality. Use “Compare my
              options”, record work and include an actual start time when known.
              Missing records are excluded.
            </p>
          ) : (
            <div className="text-sm">
              <p>
                Estimate error: <strong>{data.evaluated.brier_score}</strong>{" "}
                (Brier score; lower is closer).
              </p>
              <p className="mt-2">
                Earlier records: {data.earlier.brier_score ?? "—"} (
                {data.earlier.count}) · Later records:{" "}
                {data.later.brier_score ?? "—"} ({data.later.count}). Changes in
                task difficulty can affect this comparison.
              </p>
            </div>
          )}
          <details className="mt-3 text-xs text-slate-500">
            <summary>What counts and what does not</summary>
            <p className="mt-2">
              {data.note} {data.window}
              {data.by_model?.map((model) => (
                <span className="mt-2 block" key={model.model_version}>
                  Model {model.model_version}: {model.count} matched results,
                  error {model.brier_score ?? "—"}.
                </span>
              ))}
            </p>
          </details>
        </>
      )}
    </section>
  );
}
