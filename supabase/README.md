# HabitTrace Supabase schemas

This directory contains SQL for two separate data boundaries.

## Files

| File | Target | Purpose |
|---|---|---|
| `schema.sql` | Primary application project | Profiles, tasks, executions, prediction cache, RLS, signup trigger, and indexes |
| `task_notes.sql` | Primary application project | Optional `tasks.notes` column for existing databases |
| `google_calendar_schema.sql` | Primary application project | Encrypted Google connection records and task-to-event links |
| `group_scheduling_schema.sql` | Primary application project | Groups, invite-code memberships, and shared group tasks |
| `ai_schema.sql` | AI V2 project | AI plan inputs, outcomes, confirmed reasons, model versions, predictions, time recommendations, constraints, triggers, indexes, and RLS |
| `verify_ai_schema.sql` | AI V2 project | Read-only post-deployment verification queries |

## Primary application schema

Run `schema.sql` in the Supabase SQL Editor for the project used by frontend authentication and the V1 FastAPI services.
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
