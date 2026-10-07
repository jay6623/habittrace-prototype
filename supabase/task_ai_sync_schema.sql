-- Run in the PRIMARY Supabase project after schema.sql (not the AI project).
-- Task writes and their immutable AI delivery jobs commit together. No network
-- calls run inside the transaction. Existing tasks are not backfilled silently.
begin;

alter table public.tasks
  add column if not exists timezone_name text not null default 'UTC',
  add column if not exists ai_plan_input_id uuid,
  add column if not exists ai_sync_status text not null default 'unlinked'
    check (ai_sync_status in ('unlinked', 'pending', 'synced')),
  add column if not exists ai_plan_details jsonb not null default '{}'::jsonb;

create table if not exists public.task_ai_sync_jobs (
  id uuid primary key default gen_random_uuid(),
  sequence bigint generated always as identity unique,
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'synced')),
  created_at timestamptz not null default clock_timestamp(),
  synced_at timestamptz
);
create index if not exists idx_task_ai_sync_pending
  on public.task_ai_sync_jobs(user_id, task_id, sequence) where status = 'pending';
alter table public.task_ai_sync_jobs enable row level security;
revoke all on public.task_ai_sync_jobs from anon, authenticated;
grant select, insert, update, delete on public.task_ai_sync_jobs to service_role;
grant usage, select on sequence public.task_ai_sync_jobs_sequence_seq to service_role;

create or replace function public.prepare_task_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.ai_plan_input_id := gen_random_uuid();
    new.ai_sync_status := 'pending';
  elsif row(new.title, new.notes, new.task_category, new.planned_start_time,
            new.planned_date, new.planned_duration_min, new.importance,
            new.energy_level, new.focus_level, new.timezone_name, new.ai_plan_details)
       is distinct from
        row(old.title, old.notes, old.task_category, old.planned_start_time,
            old.planned_date, old.planned_duration_min, old.importance,
            old.energy_level, old.focus_level, old.timezone_name, old.ai_plan_details)
        or (old.ai_plan_input_id is null and old.task_status = 'pending'
            and new.ai_sync_status = 'pending') then
    new.ai_plan_input_id := gen_random_uuid();
    new.ai_sync_status := 'pending';
  else
    -- Browser task policies cannot be used to forge delivery acknowledgments.
    new.ai_plan_input_id := old.ai_plan_input_id;
    if coalesce(auth.role(), '') <> 'service_role' then
      new.ai_sync_status := old.ai_sync_status;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.enqueue_task_ai_sync()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  parent_id uuid;
  snapshot_time timestamptz := clock_timestamp();
  start_time timestamptz;
  before_count integer;
  before_minutes integer;
  day_minutes integer;
  previous_end timestamptz;
begin
  if tg_op = 'UPDATE' then
    if new.ai_plan_input_id is not distinct from old.ai_plan_input_id then
      return new;
    end if;
    parent_id := old.ai_plan_input_id;
  end if;
  start_time := (new.planned_date + new.planned_start_time::time)
                at time zone new.timezone_name;
  select count(*) filter (where s.start_at < start_time),
         coalesce(sum(s.duration) filter (where s.start_at < start_time), 0),
         coalesce(sum(s.duration), 0) + new.planned_duration_min,
         (array_agg(s.start_at + s.duration * interval '1 minute'
                    order by s.start_at desc)
           filter (where s.start_at < start_time))[1]
  into before_count, before_minutes, day_minutes, previous_end
  from (
    select (t.planned_date + t.planned_start_time::time)
              at time zone t.timezone_name as start_at,
           t.planned_duration_min as duration
    from public.tasks t
    where t.user_id = new.user_id and t.id <> new.id
      and t.planned_date between new.planned_date - 1 and new.planned_date + 1
  ) s
  where (s.start_at at time zone new.timezone_name)::date = new.planned_date;

  insert into public.task_ai_sync_jobs(id, task_id, user_id, payload, created_at)
  values (new.ai_plan_input_id, new.id, new.user_id,
    jsonb_build_object(
      'id', new.ai_plan_input_id, 'user_id', new.user_id,
      'parent_plan_input_id', parent_id,
      'input_source', case when parent_id is null then 'user' else 'reschedule' end,
      'title', new.title, 'description', new.notes, 'category', new.task_category,
      'planned_start', start_time, 'planned_duration_minutes', new.planned_duration_min,
      'importance', new.importance, 'difficulty', coalesce(new.ai_plan_details->'difficulty', '3'::jsonb),
      'required_energy', new.energy_level, 'required_focus', new.focus_level,
      -- Required effort is not a measurement of the user's current state.
      'current_energy', new.ai_plan_details->'current_energy',
      'current_focus', new.ai_plan_details->'current_focus',
      'sleep_hours', new.ai_plan_details->'sleep_hours',
      'stress_level', new.ai_plan_details->'stress_level',
      'deadline_at', new.ai_plan_details->'deadline_at',
      'is_fixed_time', coalesce(new.ai_plan_details->'is_fixed_time', 'true'::jsonb),
      'timezone_name', new.timezone_name, 'created_at', snapshot_time,
      'tasks_before_count', before_count, 'planned_minutes_before', before_minutes,
      'daily_planned_minutes', day_minutes,
      'minutes_since_previous', case when previous_end is null then null
        else greatest(0, floor(extract(epoch from (start_time - previous_end)) / 60)) end
    ), snapshot_time);
  return new;
end;
$$;

revoke all on function public.prepare_task_ai_sync() from public;
revoke all on function public.enqueue_task_ai_sync() from public;
drop trigger if exists trg_prepare_task_ai_sync on public.tasks;
create trigger trg_prepare_task_ai_sync before insert or update on public.tasks
  for each row execute function public.prepare_task_ai_sync();
drop trigger if exists trg_enqueue_task_ai_sync on public.tasks;
create trigger trg_enqueue_task_ai_sync after insert or update on public.tasks
  for each row execute function public.enqueue_task_ai_sync();

commit;
