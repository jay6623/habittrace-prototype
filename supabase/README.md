# HabitTrace Supabase schemas

This directory contains SQL for two separate data boundaries.

## Files

| File | Target | Purpose |
|---|---|---|
| `schema.sql` | Primary application project | Profiles, tasks, executions, prediction cache, RLS, signup trigger, and indexes |
| `task_notes.sql` | Primary application project | Optional `tasks.notes` column for existing databases |
| `task_ai_sync_schema.sql` | Primary application project | Durable task-to-AI links and transactional snapshot delivery jobs |
| `execution_outcome_sync_schema.sql` | Primary application project | Measured execution outcomes, idempotent logging, and durable delivery jobs |
| `ai_outcome_delivery_schema.sql` | AI V2 project | Atomic versioned outcome/reason delivery and withdrawal of ineligible labels |
| `google_calendar_schema.sql` | Primary application project | Encrypted Google connection records and task-to-event links |
| `group_scheduling_schema.sql` | Primary application project | Groups, invite-code memberships, and shared group tasks |
| `profile_avatar.sql` | Primary application project | Optional `profiles.avatar_url` for Groups member photos |
| `ai_schema.sql` | AI V2 project | AI plan inputs, outcomes, confirmed reasons, model versions, predictions, time recommendations, constraints, triggers, indexes, and RLS |
| `verify_ai_schema.sql` | AI V2 project | Read-only post-deployment verification queries |

## Primary application schema

Run `schema.sql` in the Supabase SQL Editor for the project used by frontend authentication and the V1 FastAPI services.
Run `task_ai_sync_schema.sql` in that same primary project **before deploying
the server-owned task/AI linking code**. Do not run it in the AI project.
Run `google_calendar_schema.sql` in the same project when enabling Google Calendar.
Run `group_scheduling_schema.sql` in the same project to enable group scheduling. Its tables are backend-only: RLS is enabled with no browser policies, and the FastAPI service enforces group membership on every query.

The schema manages:

- `profiles`, linked one-to-one with `auth.users`
- `tasks`, scoped by `user_id`
- `executions`, including nullable end/status fields for an active run
- `predictions`, used as an optional V1 result cache
- RLS ownership policies using `auth.uid()`
- A signup trigger that creates a profile from Auth metadata
- Date and user query indexes
- `idx_executions_one_active_per_task`, a partial unique index that prevents two open executions for one task
- backend-only `calendar_connections` and `calendar_event_links` tables when the optional Calendar schema is applied

The FastAPI backend uses a service-role client, so it must still apply the verified JWT user's UUID explicitly on every query. RLS is defense in depth and protects direct browser access; it does not replace backend ownership filters.

## Task-to-AI delivery

Task inserts and planning edits atomically capture an immutable payload in the
primary project's backend-only `task_ai_sync_jobs` table. Each job has a stable
UUID that becomes the AI plan ID. Edits reference the previous UUID; retries
deliver parents first and reuse IDs rather than create duplicate inputs.
Schedule context and the snapshot timestamp are captured during the task write,
not recalculated after a delayed retry. Effort requirements are not copied into
the user's optional current-energy/current-focus observations.

The backend attempts delivery after writes and when reading individual tasks.
`GET /tasks` retries up to three pending tasks and stops at the first failure.
`POST /tasks/{task_id}/ai-plan` explicitly retries delivery. There is no background
worker: jobs for inactive users wait for a read or explicit retry. A request
processes at most 100 revisions of one task. AI downtime leaves the primary task
saved with `ai_sync_status=pending`; API responses expose `ai_plan_input_id` only
after delivery is acknowledged. Links are shared across devices and sign-outs.

Existing browser-only links are not imported or trusted. Existing task rows stay
`unlinked` until edited or explicitly linked while pending. A legacy completed
task cannot be linked through the retry endpoint, preventing retrospective
outcomes from silently manufacturing earlier planning inputs. Historical AI rows
are preserved. Outcome delivery requires the two additional migrations below.

Verification after migration (read-only):

```sql
select ai_sync_status, count(*) from public.tasks group by ai_sync_status;
select status, count(*) from public.task_ai_sync_jobs group by status;
select t.id from public.tasks t
left join public.task_ai_sync_jobs j on j.id = t.ai_plan_input_id
where t.ai_plan_input_id is not null and j.id is null;
```

The last query should return no rows. Isolated PostgreSQL regression checks are
available at `supabase/tests/task_ai_sync.test.mjs`; run with Node and a local
PGlite installation path as its argument. They use no production credentials.

## Execution outcomes and failure reasons

Apply migrations before deploying the updated execution API and frontend:

1. **Primary project:** `schema.sql` → `task_ai_sync_schema.sql` →
   `execution_outcome_sync_schema.sql`.
2. **AI project:** `ai_schema.sql` → `ai_outcome_delivery_schema.sql`.

These migrations do not infer progress or backfill historical execution rows.
New partial results require an explicit completion ratio; completed results use
1, and abandoned/not-started results use 0. Not-started results contain no actual
timestamps or interruption events. Missing outcomes and open timers never create
failure labels. Unknown legacy failure progress remains unknown. Active minutes
are nullable; elapsed wall time is not silently presented as focused work time.

The primary execution transaction also updates the task status and captures an
immutable outcome delivery job. Execution records retain the AI plan ID captured
at their start even if the task is edited later. Manual-log requests carry a
user-scoped idempotency key; retries return the original execution. The current
frontend uses the task UUID as that key and uses the revision endpoint to correct
an already-recorded result.

AI delivery uses a backend-only RPC to update the result and its confirmed reason
in one transaction. A monotonically increasing revision and plan lock prevent old
retries from overwriting newer corrections. Corrections to success remove old
failure reasons. Inputs captured after execution began, or after the scheduled
start of a not-started plan, are excluded from learning. A correction that makes
an existing label ineligible withdraws that label; a retained delivery version
prevents delayed requests from resurrecting it. Primary user records remain.

Delivery runs after writes, on execution-list reads (including Today’s active
timer query), and via `POST /executions/{execution_id}/ai-outcome`. Reads retry at
most three pending executions and stop on an outage; each execution processes at
most 100 queued revisions. There is no background worker or offline client write
queue. A failed primary request still requires a user retry; a successful primary
save survives an AI outage without relying on another browser request.

`ai_outcome_sync_status` is `unlinked`, `pending`, `synced`, or `ineligible`.
Read-only primary checks:

```sql
select ai_outcome_sync_status, count(*) from public.executions group by 1;
select status, count(*) from public.execution_ai_sync_jobs group by 1;
select e.id from public.executions e
left join public.execution_ai_sync_jobs j on j.id = e.ai_outcome_job_id
where e.ai_outcome_job_id is not null and j.id is null;
```

The last query should return no rows. PostgreSQL regression checks are in
`supabase/tests/execution_outcome_sync.test.mjs`.

## AI V2 schema

Run `ai_schema.sql` against the isolated AI project. It creates or aligns these tables:

- `ai_plan_inputs`
- `ai_plan_outcomes`
- `ai_failure_reason_definitions`
- `ai_outcome_failure_reasons`
- `ai_model_versions`
- `ai_success_predictions`
- `ai_failure_predictions`
- `ai_time_recommendations`
- `ai_time_candidates`
- `ai_daily_schedules`

The script enables RLS but intentionally creates no browser-access policies. AI V2 access goes through FastAPI and its backend-only service-role client.

## Deployment procedure

1. Back up an existing Supabase database.
2. Open the SQL Editor in the correct project.
3. Run the complete schema file in one operation.
4. Do not ignore transaction or constraint errors; inspect existing rows that violate the current contract.
5. For AI V2, run `verify_ai_schema.sql` and review every result before connecting production traffic.

`CREATE TABLE IF NOT EXISTS` cannot repair every arbitrary old or partial table definition. Treat future changes as versioned migrations and verify existing environments explicitly.

## Backend environment

Primary project credentials belong in `backend/.env`:

```dotenv
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_KEY=your-primary-service-role-secret
SUPABASE_ANON_KEY=your-primary-anon-key
```

AI V2 credentials also remain backend-only:

```dotenv
AI_SUPABASE_URL=https://YOUR_AI_PROJECT_REF.supabase.co
AI_SUPABASE_SERVICE_ROLE_KEY=your-ai-service-role-secret
```

Never place either service-role key in a frontend `.env.local`, a `NEXT_PUBLIC_` variable, browser code, fixtures, logs, or source control.

## Current status model

Primary V1 task and execution rows use `pending`, `success`, and `failed`. An active execution has `actual_end_time = null` and `task_status = null` until completion.

AI V2 outcomes use `not_started`, `partial`, `completed`, and `abandoned`. The frontend maps mobile choices to both models without changing the primary table contract.
