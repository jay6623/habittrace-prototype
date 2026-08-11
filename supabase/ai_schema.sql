-- HabitTrace AI-only database schema for Supabase PostgreSQL
--
-- Paste this entire file into Supabase SQL Editor and click Run once.
-- This script bootstraps the AI tables and aligns their safety constraints.
-- It does NOT create or modify:
--   - Supabase Auth triggers
--   - browser-access Row Level Security policies
--   - database roles or grants
--   - Storage buckets
--   - frontend/backend tables
--   - legacy HabitTrace tables
--
-- CREATE TABLE IF NOT EXISTS cannot repair arbitrary older/partial schemas.
-- Apply future changes as versioned migrations and inspect the verification
-- queries at the bottom before connecting production code.

begin;

-- -----------------------------------------------------------------------------
-- 1. Plan inputs: information known before execution
-- -----------------------------------------------------------------------------

create table if not exists public.ai_plan_inputs (
  id uuid primary key default gen_random_uuid(),

  -- Use the Supabase Auth user UUID here later, but this schema deliberately
  -- does not create a foreign key or modify auth.users.
  user_id uuid not null,

  -- A changed or rescheduled plan should be inserted as a new row.
  parent_plan_input_id uuid references public.ai_plan_inputs(id) on delete set null,
  input_source text not null default 'user'
    check (input_source in ('user', 'recommendation', 'reschedule', 'synthetic')),

  title text not null check (char_length(btrim(title)) between 1 and 200),
  description text,
  category text not null,
  planned_start timestamptz not null,
  planned_duration_minutes integer not null
    check (planned_duration_minutes between 1 and 10080),
  deadline_at timestamptz,

  importance smallint not null default 3 check (importance between 1 and 5),
  difficulty smallint not null default 3 check (difficulty between 1 and 5),
  required_energy smallint not null default 3 check (required_energy between 1 and 5),
  required_focus smallint not null default 3 check (required_focus between 1 and 5),

  -- Optional user state captured at planning time.
  current_energy smallint check (current_energy between 1 and 5),
  current_focus smallint check (current_focus between 1 and 5),
  sleep_hours numeric(4,2) check (sleep_hours between 0 and 24),
  stress_level smallint check (stress_level between 1 and 5),

  -- Schedule context known at prediction time.
  tasks_before_count integer not null default 0 check (tasks_before_count >= 0),
  planned_minutes_before integer not null default 0 check (planned_minutes_before >= 0),
  daily_planned_minutes integer not null default 0 check (daily_planned_minutes >= 0),
  minutes_since_previous integer check (minutes_since_previous >= 0),
  timezone_name text not null default 'UTC',

  is_fixed_time boolean not null default false,
  created_at timestamptz not null default now(),

  check (deadline_at is null or deadline_at >= planned_start)
);

create index if not exists idx_ai_plan_inputs_user_created
  on public.ai_plan_inputs(user_id, created_at desc);

create index if not exists idx_ai_plan_inputs_user_start
  on public.ai_plan_inputs(user_id, planned_start);

create index if not exists idx_ai_plan_inputs_category
  on public.ai_plan_inputs(category);

-- Keep plan revisions linear. Recommendation alternatives belong in
-- ai_time_candidates; only the accepted revision becomes a new plan input.
create unique index if not exists uq_ai_plan_inputs_single_child
  on public.ai_plan_inputs(parent_plan_input_id)
  where parent_plan_input_id is not null;

-- A composite parent key guarantees that a revision belongs to the same user.
create unique index if not exists uq_ai_plan_inputs_id_user
  on public.ai_plan_inputs(id, user_id);

alter table public.ai_plan_inputs
  drop constraint if exists ai_plan_inputs_parent_plan_input_id_fkey;

alter table public.ai_plan_inputs
  add constraint ai_plan_inputs_parent_plan_input_id_fkey
  foreign key (parent_plan_input_id, user_id)
  references public.ai_plan_inputs(id, user_id)
  on delete restrict;

alter table public.ai_plan_inputs
  drop constraint if exists ai_plan_inputs_source_parent_check;

alter table public.ai_plan_inputs
  add constraint ai_plan_inputs_source_parent_check
  check (
    (parent_plan_input_id is null and input_source in ('user', 'synthetic'))
    or
    (parent_plan_input_id is not null and input_source in ('recommendation', 'reschedule'))
  );

create or replace function public.validate_ai_plan_revision_cycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_plan_input_id is null then
    return new;
  end if;

  if new.parent_plan_input_id = new.id then
    raise exception 'an AI plan revision cannot be its own parent'
      using errcode = '23514';
  end if;

  if exists (
    with recursive ancestors(id, parent_plan_input_id) as (
      select p.id, p.parent_plan_input_id
      from public.ai_plan_inputs p
      where p.id = new.parent_plan_input_id

      union

      select p.id, p.parent_plan_input_id
      from public.ai_plan_inputs p
      join ancestors a on p.id = a.parent_plan_input_id
    )
    select 1 from ancestors where id = new.id
  ) then
    raise exception 'an AI plan revision cycle is not allowed'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_ai_plan_revision_cycle
  on public.ai_plan_inputs;

create trigger trg_validate_ai_plan_revision_cycle
before insert or update of parent_plan_input_id
on public.ai_plan_inputs
for each row execute function public.validate_ai_plan_revision_cycle();

-- -----------------------------------------------------------------------------
-- 2. Actual outcomes: information available only after execution
-- -----------------------------------------------------------------------------

create table if not exists public.ai_plan_outcomes (
  id uuid primary key default gen_random_uuid(),
  plan_input_id uuid not null unique
    references public.ai_plan_inputs(id) on delete cascade,

  outcome_status text not null
    check (outcome_status in ('not_started', 'partial', 'completed', 'abandoned')),
  actual_start timestamptz,
  actual_end timestamptz,
  active_minutes integer check (active_minutes >= 0),
  completion_ratio numeric(6,5) not null default 0
    check (completion_ratio between 0 and 1),
  interruption_count integer not null default 0 check (interruption_count >= 0),
  stopped_early boolean not null default false,
  user_note text,
  recorded_at timestamptz not null default now(),

  check (actual_end is null or actual_start is not null),
  check (actual_end is null or actual_end >= actual_start),
  check (outcome_status <> 'not_started' or actual_start is null)
);

create index if not exists idx_ai_plan_outcomes_recorded
  on public.ai_plan_outcomes(recorded_at);

alter table public.ai_plan_outcomes
  drop constraint if exists ai_plan_outcomes_not_started_consistency;

alter table public.ai_plan_outcomes
  add constraint ai_plan_outcomes_not_started_consistency
  check (
    outcome_status <> 'not_started'
    or (
      actual_start is null
      and actual_end is null
      and coalesce(active_minutes, 0) = 0
      and completion_ratio = 0
      and interruption_count = 0
      and stopped_early = false
    )
  );

-- Do not store a permanent success boolean. Derive the label during training.
-- Initial recommended label policy:
--   success = outcome_status = 'completed' and completion_ratio >= 0.80

-- -----------------------------------------------------------------------------
-- 3. User-confirmed failure causes
-- -----------------------------------------------------------------------------

create table if not exists public.ai_failure_reason_definitions (
  code text primary key,
  display_name text not null,
  description text not null,
  is_active boolean not null default true
);

insert into public.ai_failure_reason_definitions(code, display_name, description)
values
  ('low_readiness', 'Low readiness',
   'Low energy, focus, or motivation affected execution.'),
  ('schedule_overload', 'Schedule overload',
   'Too much surrounding scheduled work affected execution.'),
  ('underestimated_time', 'Underestimated time',
   'The plan was assigned less time than it required.'),
  ('interruption', 'Interruption',
   'Another event or distraction interrupted execution.'),
  ('unexpected_event', 'Unexpected event',
   'An unplanned external event affected execution.'),
  ('unclear_plan', 'Unclear plan',
   'The task lacked a clear scope or starting action.'),
  ('task_too_difficult', 'Task too difficult',
   'The task was more difficult than expected.'),
  ('other', 'Other',
   'A cause not represented by another option.')
on conflict (code) do update
set display_name = excluded.display_name,
    description = excluded.description,
    is_active = true;

-- Keep the current training taxonomy exact while preserving unknown historical
-- definitions as inactive rows for auditability.
update public.ai_failure_reason_definitions
set is_active = false
where code not in (
  'low_readiness',
  'schedule_overload',
  'underestimated_time',
  'interruption',
  'unexpected_event',
  'unclear_plan',
  'task_too_difficult',
  'other'
);

create table if not exists public.ai_outcome_failure_reasons (
  id uuid primary key default gen_random_uuid(),
  outcome_id uuid not null
    references public.ai_plan_outcomes(id) on delete cascade,
  reason_code text not null
    references public.ai_failure_reason_definitions(code) on delete restrict,
  is_primary boolean not null default false,
  user_confirmed boolean not null default true,
  created_at timestamptz not null default now(),
  unique(outcome_id, reason_code)
);

create unique index if not exists uq_ai_primary_failure_reason
  on public.ai_outcome_failure_reasons(outcome_id)
  where is_primary = true;

alter table public.ai_outcome_failure_reasons
  drop constraint if exists ai_outcome_failure_reasons_user_confirmed_check;

alter table public.ai_outcome_failure_reasons
  add constraint ai_outcome_failure_reasons_user_confirmed_check
  check (user_confirmed = true);

-- Validate the complete multi-row reason set at transaction commit. This lets
-- FastAPI insert one primary and multiple secondary rows in one request while
-- preventing incomplete or model-generated truth from entering the table.
create or replace function public.validate_ai_failure_reason_truth()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  target_outcome_id uuid;
  target_outcome_ids uuid[];
  target_status text;
  target_completion numeric;
  assignment_count integer;
  primary_count integer;
begin
  if tg_table_name = 'ai_plan_outcomes' then
    target_outcome_ids := array[
      case when tg_op = 'DELETE' then old.id else new.id end
    ];
  elsif tg_op = 'INSERT' then
    target_outcome_ids := array[new.outcome_id];
  elsif tg_op = 'DELETE' then
    target_outcome_ids := array[old.outcome_id];
  else
    target_outcome_ids := array[old.outcome_id, new.outcome_id];
  end if;

  if tg_table_name = 'ai_outcome_failure_reasons'
     and tg_op in ('INSERT', 'UPDATE') then
    if not exists (
      select 1
      from public.ai_failure_reason_definitions d
      where d.code = new.reason_code and d.is_active
    ) then
      raise exception 'inactive failure reasons cannot be assigned'
        using errcode = '23514';
    end if;
  end if;

  foreach target_outcome_id in array target_outcome_ids loop
    select o.outcome_status, o.completion_ratio
    into target_status, target_completion
    from public.ai_plan_outcomes o
    where o.id = target_outcome_id;

    if not found then
      continue;
    end if;

    select
      count(*)::integer,
      count(*) filter (where r.is_primary)::integer
    into assignment_count, primary_count
    from public.ai_outcome_failure_reasons r
    where r.outcome_id = target_outcome_id;

    if assignment_count = 0 then
      continue;
    end if;

    if target_status = 'completed' and target_completion >= 0.80 then
      raise exception 'a successful outcome cannot have failure reasons'
        using errcode = '23514';
    end if;

    if primary_count <> 1 then
      raise exception 'a failure reason set must contain exactly one primary reason'
        using errcode = '23514';
    end if;
  end loop;

  return null;
end;
$$;

drop trigger if exists trg_validate_ai_failure_reason_set
  on public.ai_outcome_failure_reasons;

create constraint trigger trg_validate_ai_failure_reason_set
after insert or update or delete
on public.ai_outcome_failure_reasons
deferrable initially deferred
for each row execute function public.validate_ai_failure_reason_truth();

drop trigger if exists trg_validate_ai_outcome_failure_truth
  on public.ai_plan_outcomes;

create constraint trigger trg_validate_ai_outcome_failure_truth
after update
on public.ai_plan_outcomes
deferrable initially deferred
for each row execute function public.validate_ai_failure_reason_truth();

-- Triggers protect future writes but do not scan rows that predate the trigger.
-- Fail the whole transaction if an existing AI dataset is already inconsistent.
do $$
begin
  if exists (
    with recursive revision_walk(start_id, id, parent_plan_input_id, path, has_cycle) as (
      select p.id, p.id, p.parent_plan_input_id, array[p.id], false
      from public.ai_plan_inputs p

      union all

      select
        w.start_id,
        p.id,
        p.parent_plan_input_id,
        w.path || p.id,
        p.id = any(w.path)
      from revision_walk w
      join public.ai_plan_inputs p on p.id = w.parent_plan_input_id
      where not w.has_cycle
    )
    select 1 from revision_walk where has_cycle
  ) then
    raise exception 'existing AI plan data contains a revision cycle'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.ai_outcome_failure_reasons r
    group by r.outcome_id
    having count(*) filter (where r.is_primary) <> 1
  ) then
    raise exception 'existing failure reason data must have exactly one primary per outcome'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.ai_outcome_failure_reasons r
    join public.ai_plan_outcomes o on o.id = r.outcome_id
    where o.outcome_status = 'completed' and o.completion_ratio >= 0.80
  ) then
    raise exception 'existing successful outcomes cannot have failure reasons'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.ai_outcome_failure_reasons r
    join public.ai_failure_reason_definitions d on d.code = r.reason_code
    where not d.is_active
  ) then
    raise exception 'existing assignments contain unsupported failure reason codes'
      using errcode = '23514';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Trained model registry
-- -----------------------------------------------------------------------------

create table if not exists public.ai_model_versions (
  id uuid primary key default gen_random_uuid(),
  model_type text not null
    check (model_type in ('success', 'failure_reason')),
  model_name text not null,
  version text not null,
  status text not null default 'staging'
    check (status in ('training', 'staging', 'production', 'retired')),
  artifact_uri text,
  feature_schema_version text not null,
  label_policy jsonb not null default '{}'::jsonb,
  metrics jsonb not null default '{}'::jsonb,
  trained_at timestamptz,
  created_at timestamptz not null default now(),
  unique(model_type, version)
);

create unique index if not exists uq_ai_production_model_type
  on public.ai_model_versions(model_type)
  where status = 'production';

-- -----------------------------------------------------------------------------
-- 5. Success/failure probability predictions
-- -----------------------------------------------------------------------------

create table if not exists public.ai_success_predictions (
  id uuid primary key default gen_random_uuid(),
  plan_input_id uuid not null
    references public.ai_plan_inputs(id) on delete cascade,
  model_version_id uuid not null
    references public.ai_model_versions(id) on delete restrict,
  success_probability numeric(7,6) not null
    check (success_probability between 0 and 1),

  -- Exact derived features used for this prediction. This makes predictions
  -- reproducible without mixing these values into the raw input tables.
  feature_snapshot jsonb not null default '{}'::jsonb,
  explanation_snapshot jsonb not null default '{}'::jsonb,
  predicted_at timestamptz not null default now()
);

create index if not exists idx_ai_success_predictions_plan_time
  on public.ai_success_predictions(plan_input_id, predicted_at desc);

create index if not exists idx_ai_success_predictions_model
  on public.ai_success_predictions(model_version_id);

-- Failure probability is calculated as: 1 - success_probability.

-- -----------------------------------------------------------------------------
-- 6. Predicted failure-reason probabilities
-- -----------------------------------------------------------------------------

create table if not exists public.ai_failure_predictions (
  id uuid primary key default gen_random_uuid(),
  success_prediction_id uuid not null unique
    references public.ai_success_predictions(id) on delete cascade,
  model_version_id uuid not null
    references public.ai_model_versions(id) on delete restrict,

  -- Example:
  -- {"low_readiness": 0.42, "schedule_overload": 0.31}
  reason_probabilities jsonb not null,
  explanation_snapshot jsonb not null default '{}'::jsonb,
  predicted_at timestamptz not null default now()
);

create index if not exists idx_ai_failure_predictions_model
  on public.ai_failure_predictions(model_version_id);

-- -----------------------------------------------------------------------------
-- 7. Time recommendation requests and candidate scores
-- -----------------------------------------------------------------------------

create table if not exists public.ai_time_recommendations (
  id uuid primary key default gen_random_uuid(),
  plan_input_id uuid not null
    references public.ai_plan_inputs(id) on delete cascade,
  model_version_id uuid not null
    references public.ai_model_versions(id) on delete restrict,
  earliest_start timestamptz not null,
  latest_end timestamptz not null,
  slot_interval_minutes integer not null default 30
    check (slot_interval_minutes between 5 and 240),
  minimum_buffer_minutes integer not null default 15
    check (minimum_buffer_minutes between 0 and 1440),
  status text not null default 'generated'
    check (status in ('generated', 'accepted', 'modified', 'dismissed', 'expired')),
  selected_candidate_id uuid,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  check (earliest_start < latest_end)
);

create index if not exists idx_ai_time_recommendations_plan
  on public.ai_time_recommendations(plan_input_id, created_at desc);

create index if not exists idx_ai_time_recommendations_model
  on public.ai_time_recommendations(model_version_id);

create table if not exists public.ai_time_candidates (
  id uuid primary key default gen_random_uuid(),
  recommendation_id uuid not null
    references public.ai_time_recommendations(id) on delete cascade,
  candidate_start timestamptz not null,
  candidate_end timestamptz not null,
  predicted_success_probability numeric(7,6) not null
    check (predicted_success_probability between 0 and 1),
  conflict_penalty numeric(7,6) not null default 0
    check (conflict_penalty between 0 and 1),
  overload_penalty numeric(7,6) not null default 0
    check (overload_penalty between 0 and 1),
  preference_penalty numeric(7,6) not null default 0
    check (preference_penalty between 0 and 1),
  final_score numeric(9,6) not null,
  rank integer not null check (rank > 0),
  feature_snapshot jsonb not null default '{}'::jsonb,
  reason_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (candidate_start < candidate_end),
  unique(recommendation_id, candidate_start),
  unique(recommendation_id, rank)
);

create index if not exists idx_ai_time_candidates_rank
  on public.ai_time_candidates(recommendation_id, rank);

create unique index if not exists uq_ai_time_candidates_id_recommendation
  on public.ai_time_candidates(id, recommendation_id);

alter table public.ai_time_recommendations
  drop constraint if exists ai_time_recommendations_selected_candidate_fkey;

alter table public.ai_time_recommendations
  add constraint ai_time_recommendations_selected_candidate_fkey
  foreign key (selected_candidate_id, id)
  references public.ai_time_candidates(id, recommendation_id)
  deferrable initially deferred;

-- -----------------------------------------------------------------------------
-- 8. Backend-only access boundary
-- -----------------------------------------------------------------------------
--
-- These AI tables are accessed through FastAPI with the Supabase service_role
-- key. No anon/authenticated policies are created here, so browser clients
-- cannot read or mutate the tables directly. The service_role bypasses RLS.

alter table public.ai_plan_inputs enable row level security;
alter table public.ai_plan_outcomes enable row level security;
alter table public.ai_failure_reason_definitions enable row level security;
alter table public.ai_outcome_failure_reasons enable row level security;
alter table public.ai_model_versions enable row level security;
alter table public.ai_success_predictions enable row level security;
alter table public.ai_failure_predictions enable row level security;
alter table public.ai_time_recommendations enable row level security;
alter table public.ai_time_candidates enable row level security;

commit;

-- Verification query:
-- select table_name
-- from information_schema.tables
-- where table_schema = 'public' and table_name like 'ai_%'
-- order by table_name;
