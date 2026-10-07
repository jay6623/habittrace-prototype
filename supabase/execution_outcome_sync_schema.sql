-- PRIMARY project, after schema.sql and task_ai_sync_schema.sql.
begin;
alter table public.executions
  add column if not exists outcome_status text
    check (outcome_status in ('not_started', 'partial', 'completed', 'abandoned')),
  add column if not exists completion_ratio numeric(6,5) check (completion_ratio between 0 and 1),
  add column if not exists active_minutes integer check (active_minutes >= 0),
  add column if not exists ai_plan_input_id uuid,
  add column if not exists ai_outcome_job_id uuid,
  add column if not exists ai_learning_eligible boolean not null default false,
  add column if not exists ai_outcome_sync_status text not null default 'unlinked'
    check (ai_outcome_sync_status in ('unlinked', 'pending', 'synced', 'ineligible')),
  add column if not exists idempotency_key uuid;
create unique index if not exists uq_execution_idempotency
  on public.executions(user_id, idempotency_key) where idempotency_key is not null;
drop index if exists public.idx_executions_one_active_per_task;
create unique index idx_executions_one_active_per_task on public.executions(task_id)
  where actual_end_time is null and task_status is null;

create table if not exists public.execution_ai_sync_jobs (
  id uuid primary key,
  sequence bigint generated always as identity unique,
  execution_id uuid not null references public.executions(id) on delete cascade,
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null,
  plan_input_id uuid not null,
  payload jsonb not null,
  primary_reason_code text,
  status text not null default 'pending' check (status in ('pending', 'synced')),
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists idx_execution_ai_pending
  on public.execution_ai_sync_jobs(user_id, execution_id, sequence) where status = 'pending';
alter table public.execution_ai_sync_jobs enable row level security;
revoke all on public.execution_ai_sync_jobs from anon, authenticated;
grant select, insert, update, delete on public.execution_ai_sync_jobs to service_role;
grant usage, select on sequence public.execution_ai_sync_jobs_sequence_seq to service_role;

create or replace function public.prepare_execution_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  plan_created_at timestamptz;
  planned_start timestamptz;
begin
  if not exists (select 1 from public.tasks t where t.id = new.task_id and t.user_id = new.user_id) then
    raise exception 'Execution task not found' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    select t.ai_plan_input_id into new.ai_plan_input_id from public.tasks t where t.id = new.task_id;
  else
    -- Corrections stay attached to the plan known when execution began, even
    -- if the task was subsequently edited on another device.
    new.ai_plan_input_id := old.ai_plan_input_id;
    if row(new.actual_start_time, new.actual_end_time, new.interruption_count,
           new.stopped_early, new.task_status, new.failure_reason, new.outcome_status,
           new.completion_ratio, new.active_minutes) is not distinct from
       row(old.actual_start_time, old.actual_end_time, old.interruption_count,
           old.stopped_early, old.task_status, old.failure_reason, old.outcome_status,
           old.completion_ratio, old.active_minutes) then
      new.ai_outcome_job_id := old.ai_outcome_job_id;
      new.ai_learning_eligible := old.ai_learning_eligible;
      if coalesce(auth.role(), '') <> 'service_role' then
        new.ai_outcome_sync_status := old.ai_outcome_sync_status;
      end if;
      return new;
    end if;
  end if;
  new.ai_outcome_job_id := null;
  new.ai_learning_eligible := false;
  new.ai_outcome_sync_status := 'unlinked';
  if new.task_status is null then
    if new.outcome_status is not null or new.completion_ratio is not null then
      raise exception 'An unfinished execution cannot have an outcome' using errcode = '23514';
    end if;
    return new;
  end if;
  if new.outcome_status is null then
    -- Old failed records have unknown progress, not an invented zero or 50%.
    -- A correction from a newer client must also withdraw any prior AI label.
    if new.ai_plan_input_id is not null then
      new.ai_outcome_job_id := gen_random_uuid();
      new.ai_outcome_sync_status := 'pending';
    end if;
    return new;
  end if;
  if new.completion_ratio is null
     or (new.outcome_status = 'completed' and (new.task_status <> 'success' or new.completion_ratio <> 1))
     or (new.outcome_status <> 'completed' and new.task_status <> 'failed')
     or (new.outcome_status = 'partial' and not (new.completion_ratio > 0 and new.completion_ratio < 1))
     or (new.outcome_status in ('not_started', 'abandoned') and new.completion_ratio <> 0) then
    raise exception 'Inconsistent outcome and completion ratio' using errcode = '23514';
  end if;
  if new.outcome_status = 'not_started' then
    if new.actual_start_time is not null or new.actual_end_time is not null
       or coalesce(new.active_minutes, 0) <> 0 or new.interruption_count <> 0 or new.stopped_early then
      raise exception 'Not-started outcomes cannot contain execution activity' using errcode = '23514';
    end if;
  else
    if new.actual_start_time is null or new.actual_end_time is null
       or new.actual_end_time::timestamptz < new.actual_start_time::timestamptz
       or new.actual_end_time::timestamptz > clock_timestamp() + interval '5 minutes'
       or new.active_minutes > floor(extract(epoch from
           (new.actual_end_time::timestamptz - new.actual_start_time::timestamptz)) / 60) then
      raise exception 'Invalid actual execution times' using errcode = '23514';
    end if;
  end if;
  if new.ai_plan_input_id is null then return new; end if;
  select j.created_at, (j.payload->>'planned_start')::timestamptz
    into plan_created_at, planned_start
    from public.task_ai_sync_jobs j where j.id = new.ai_plan_input_id and j.user_id = new.user_id;
  if plan_created_at is null or plan_created_at > coalesce(new.actual_start_time::timestamptz, planned_start) then
    -- Retrospective records remain in the product but do not become training
    -- labels for inputs captured after the execution had already started.
    new.ai_learning_eligible := false;
  else
    new.ai_learning_eligible := true;
  end if;
  new.ai_outcome_job_id := gen_random_uuid();
  new.ai_outcome_sync_status := 'pending';
  return new;
end;
$$;

create or replace function public.enqueue_execution_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.task_status is not null then
    -- Task status, outcome facts, and delivery intent commit together.
    update public.tasks set task_status = new.task_status where id = new.task_id and user_id = new.user_id;
  end if;
  if new.ai_outcome_job_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.ai_outcome_job_id is not distinct from old.ai_outcome_job_id then
    return new;
  end if;
  insert into public.execution_ai_sync_jobs(id, execution_id, task_id, user_id, plan_input_id, payload, primary_reason_code)
  values (new.ai_outcome_job_id, new.id, new.task_id, new.user_id, new.ai_plan_input_id,
    jsonb_build_object(
      'outcome_status', new.outcome_status, 'completion_ratio', new.completion_ratio,
      'actual_start', new.actual_start_time, 'actual_end', new.actual_end_time,
      'active_minutes', new.active_minutes, 'interruption_count', new.interruption_count,
      'stopped_early', new.stopped_early, 'recorded_at', clock_timestamp()
      , 'learning_eligible', new.ai_learning_eligible
    ), case when new.task_status = 'success' then null else new.failure_reason end);
  return new;
end;
$$;
revoke all on function public.prepare_execution_ai_sync() from public;
revoke all on function public.enqueue_execution_ai_sync() from public;
drop trigger if exists trg_prepare_execution_ai_sync on public.executions;
create trigger trg_prepare_execution_ai_sync before insert or update on public.executions
  for each row execute function public.prepare_execution_ai_sync();
drop trigger if exists trg_enqueue_execution_ai_sync on public.executions;
create trigger trg_enqueue_execution_ai_sync after insert or update on public.executions
  for each row execute function public.enqueue_execution_ai_sync();
commit;
