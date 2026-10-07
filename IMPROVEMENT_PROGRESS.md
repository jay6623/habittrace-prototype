# HabitTrace improvement sequence

## 1. Durable task-to-AI linking — implemented locally

- Primary task writes capture delivery jobs in the same PostgreSQL transaction.
- Stable snapshot IDs, parent-first revision delivery, idempotent retries, and
  conditional acknowledgments protect against outages and concurrent edits.
- Task API responses carry server-owned links across devices; the frontend no
  longer creates separate snapshots or trusts browser-only mappings.
- Daily schedules and coach-created tasks preserve their scheduling timezone.
- PostgreSQL regression checks cover the actual migration and AI constraints;
  backend checks cover outages, retries, ownership, and acknowledgment races.

Deployment prerequisite: apply `supabase/task_ai_sync_schema.sql` to the **primary
Supabase project**, after `schema.sql`, before deploying this code. The isolated AI
project must already have `ai_schema.sql`. No production migration or deployment
was performed. See `supabase/README.md` for verification queries and limitations.

## 2. Outcome fidelity and delivery — implemented locally

- Partial completion is an explicit percentage, with measured interruption counts
  in both recording and editing flows. Unknown legacy progress is not inferred.
- Not-started results contain no fabricated execution times; missing outcomes and
  active timers remain unlabeled. Focused work time stays nullable when unmeasured.
- Primary execution writes atomically capture delivery intent and task status.
  Manual logging retries are idempotent, including when completing an active timer.
- The AI database saves the outcome and confirmed reason together; corrections
  replace them atomically, and older retries cannot overwrite newer facts.
- Results remain attached to the plan captured at execution start. Retrospective
  inputs are excluded from learning; later corrections can withdraw a label
  without allowing a delayed retry to resurrect it.
- Writes, execution reads, and Today’s active-timer reads retry pending deliveries.

Deployment prerequisite: apply `execution_outcome_sync_schema.sql` in the primary
project after the step-1 migration, and `ai_outcome_delivery_schema.sql` in the AI
project after `ai_schema.sql`. No production migration or deployment was performed.

## 3. Observed-duration recommendations — implemented locally

- Authenticated `GET /analytics/duration-recommendation` uses only the user's
  completed executions and the immutable plan captured before execution started.
- Reads are bounded to the latest 500 completed execution records; evidence must
  have finished in the last 90 days. Each task supplies at most one observation.
- Same-name/category evidence needs 3 completions; category fallback needs 5
  completions originally planned for 75–150% of the current duration.
- Recommendations use median elapsed time (including interruptions), round to
  5-minute blocks, and stay within 5–480 minutes and ±50% of the current estimate.
  This is an observed-history heuristic, not a newly trained or validated model.
- Shared Quick Add offers an explicit history lookup, sample count, median, and
  an apply button. Sparse history and network errors preserve the entered estimate;
  changing the draft invalidates pending/stale suggestions.
- Partial, not-started, future, invalid, retrospective, unlinked, and unknown legacy
  records do not supply duration evidence. Editing excludes the current task.

No additional SQL migration is needed beyond steps 1 and 2. Their primary database
migrations must be installed first. No production migration or deployment was run.

## Remaining sequence
4. Offer reviewable replanning when work is delayed, respecting fixed commitments,
   deadlines, and breaks.
5. Connect recommendation exposure and decisions to execution results; reproduce
   predictions from full feature and personalization snapshots.
6. Add reminders and incorporate external busy intervals where useful.

Real-model promotion remains a separate data-dependent step: collect real,
consented plan/outcome pairs and evaluate against simple baselines on untouched
future data. Synthetic benchmarks do not establish real-user accuracy.

## Validation with AI Coach scope guardrail (PR #8)

- Includes the three improvements above and PR #8's scoped coach responses.
- Backend: 263 tests passed, including scope redirects and execution delivery.
- Frontend: 10 tests passed; TypeScript and the production build passed.
- PostgreSQL checks passed for both transactional plan and outcome delivery.
- Scoped Ruff checks passed. Frontend lint had no errors and one existing
  Scheduler hook dependency warning.
- These are local automated checks, not live-provider or production database tests.
  No production schema migration was executed; apply the prerequisites above
  before deploying this version. PR #9's native iOS changes are excluded.
