-- PRIMARY DB after group_planning_extensions.sql, task_ai_sync_schema.sql,
-- and execution_outcome_sync_schema.sql. No private data is copied to group tables.
begin;

alter table public.groups add column if not exists planning_timezone_name text not null default 'UTC';

alter table public.tasks add column if not exists continuation_of_task_id uuid
  references public.tasks(id) on delete set null;

create or replace function public.validate_task_continuation() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.continuation_of_task_id is null then return new; end if;
  if new.continuation_of_task_id=new.id or not exists(select 1 from tasks
    where id=new.continuation_of_task_id and user_id=new.user_id) then
    raise exception 'Continuation must reference another plan owned by the same user' using errcode='42501';
  end if;
  return new;
end $$;
drop trigger if exists check_task_continuation on public.tasks;
create trigger check_task_continuation before insert or update of continuation_of_task_id,user_id
  on public.tasks for each row execute function public.validate_task_continuation();

create table if not exists public.planning_comparisons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_task_id uuid references public.tasks(id) on delete set null,
  source_snapshot jsonb not null,
  latest_execution_id uuid,
  options jsonb not null,
  evidence jsonb not null,
  model_version text,
  shown_at timestamptz not null default clock_timestamp(),
  displayed_at timestamptz,
  selected_option_id text,
  selected_at timestamptz,
  applied_tasks jsonb,
  applied_snapshots jsonb
);
create index if not exists idx_planning_comparisons_owner on public.planning_comparisons(user_id, shown_at);
alter table public.planning_comparisons enable row level security;
revoke all on public.planning_comparisons from anon, authenticated;
grant all on public.planning_comparisons to service_role;

create table if not exists public.group_task_dependencies (
  group_id uuid not null references public.groups(id) on delete cascade,
  task_id uuid not null references public.group_tasks(id) on delete cascade,
  predecessor_id uuid not null references public.group_tasks(id) on delete cascade,
  primary key(task_id, predecessor_id), check(task_id <> predecessor_id)
);
create or replace function public.validate_group_dependency() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Serialize edge edits in one group so concurrent additions cannot create a cycle.
  perform pg_advisory_xact_lock(hashtextextended(new.group_id::text, 0));
  if not exists (select 1 from group_tasks where id=new.task_id and group_id=new.group_id)
     or not exists (select 1 from group_tasks where id=new.predecessor_id and group_id=new.group_id) then
    raise exception 'Dependencies must stay in the same group' using errcode='23514';
  end if;
  if exists (
    with recursive ancestors(id) as (
      select new.predecessor_id union
      select d.predecessor_id from group_task_dependencies d join ancestors a on d.task_id=a.id
      where d.group_id=new.group_id
    ) select 1 from ancestors where id=new.task_id
  ) then raise exception 'Dependency cycle is not allowed' using errcode='23514'; end if;
  return new;
end $$;
drop trigger if exists check_group_dependency on public.group_task_dependencies;
create trigger check_group_dependency before insert or update on public.group_task_dependencies
  for each row execute function public.validate_group_dependency();

create table if not exists public.group_project_milestones (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  title text not null check(length(trim(title)) between 1 and 120),
  due_date date not null,
  completion_criteria text not null check(length(trim(completion_criteria)) between 1 and 500),
  timezone_name text not null default 'UTC',
  task_ids uuid[] not null default '{}',
  created_at timestamptz not null default clock_timestamp(),
  confirmed_at timestamptz
);
create or replace function public.validate_milestone_tasks() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if exists(select 1 from unnest(new.task_ids) t(id) where not exists (
    select 1 from group_tasks g where g.id=t.id and g.group_id=new.group_id)) then
    raise exception 'Milestone tasks must stay in the same group' using errcode='23514';
  end if;
  return new;
end $$;
drop trigger if exists check_milestone_tasks on public.group_project_milestones;
create trigger check_milestone_tasks before insert or update on public.group_project_milestones
  for each row execute function public.validate_milestone_tasks();

alter table public.group_members
  add column if not exists shared_minutes_per_day integer check(shared_minutes_per_day between 0 and 720),
  add column if not exists capacity_until date;
alter table public.group_task_assignees
  add column if not exists shared_remaining_minutes integer check(shared_remaining_minutes between 0 and 10080),
  add column if not exists remaining_updated_at timestamptz;

create table if not exists public.group_help_requests (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  task_id uuid not null references public.group_tasks(id) on delete cascade,
  requester_id uuid not null references auth.users(id) on delete cascade,
  helper_id uuid not null references auth.users(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 300),
  status text not null default 'pending' check(status in ('pending','accepted','declined')),
  created_at timestamptz not null default clock_timestamp(),
  check(requester_id <> helper_id)
);
create unique index if not exists idx_pending_group_help on public.group_help_requests(task_id,requester_id,helper_id)
  where status='pending';
alter table public.group_task_dependencies enable row level security;
alter table public.group_project_milestones enable row level security;
alter table public.group_help_requests enable row level security;
revoke all on public.group_task_dependencies, public.group_project_milestones, public.group_help_requests from anon,authenticated;
grant all on public.group_task_dependencies, public.group_project_milestones, public.group_help_requests to service_role;

-- Apply one server-created option atomically. Only the authenticated backend can execute.
create or replace function public.apply_planning_option(p_user_id uuid,p_comparison_id uuid,p_option_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c planning_comparisons; src tasks; opt jsonb; b jsonb; result jsonb='[]'; snaps jsonb='[]';
  saved tasks; idx integer=0; latest_id uuid; group_deadline timestamptz;
begin
  select * into c from planning_comparisons where id=p_comparison_id and user_id=p_user_id for update;
  if not found then raise exception 'Comparison not found' using errcode='P0002'; end if;
  if c.selected_option_id is not null then
    if c.selected_option_id<>p_option_id then raise exception 'A different option was already applied' using errcode='23505'; end if;
    return c.applied_tasks;
  end if;
  if c.shown_at < clock_timestamp()-interval '15 minutes' then
    raise exception 'Comparison expired; compare again' using errcode='23505'; end if;
  select * into src from tasks where id=c.source_task_id and user_id=p_user_id for update;
  if not found then raise exception 'Source plan was removed' using errcode='P0002'; end if;
  -- Compare typed planning fields, not timestamp string formatting from REST/JSON.
  if row(src.title,src.notes,src.task_category,src.planned_date,src.planned_start_time::time,
    src.planned_duration_min,src.importance,src.energy_level,src.focus_level,src.timezone_name,
    src.task_status,src.source_group_task_id,src.ai_plan_input_id,src.ai_plan_details)
  is distinct from row(c.source_snapshot->>'title',c.source_snapshot->>'notes',
    c.source_snapshot->>'task_category',(c.source_snapshot->>'planned_date')::date,
    (c.source_snapshot->>'planned_start_time')::time,(c.source_snapshot->>'planned_duration_min')::integer,
    (c.source_snapshot->>'importance')::integer,(c.source_snapshot->>'energy_level')::integer,
    (c.source_snapshot->>'focus_level')::integer,c.source_snapshot->>'timezone_name',
    c.source_snapshot->>'task_status',(c.source_snapshot->>'source_group_task_id')::uuid,
    (c.source_snapshot->>'ai_plan_input_id')::uuid,c.source_snapshot->'ai_plan_details') then
    raise exception 'Source plan changed; compare again' using errcode='23505';
  end if;
  select id into latest_id from executions where task_id=src.id and user_id=p_user_id
    order by created_at desc,id desc limit 1;
  if latest_id is distinct from c.latest_execution_id then
    raise exception 'Execution changed; compare again' using errcode='23505'; end if;
  if exists(select 1 from executions where task_id=src.id and task_status is null) then
    raise exception 'Finish the running block first' using errcode='23505'; end if;
  select value into opt from jsonb_array_elements(c.options) where value->>'id'=p_option_id;
  if opt is null or not (opt->>'available')::boolean then
    raise exception 'Choose an available option' using errcode='23514'; end if;
  if src.source_group_task_id is not null then
    if c.evidence->>'shared_source_version' is not null and not exists(select 1 from group_tasks
      where id=src.source_group_task_id and updated_at=(c.evidence->>'shared_source_version')::timestamptz) then
      raise exception 'Shared work changed; compare again' using errcode='23505'; end if;
    if not exists(select 1 from group_task_assignees a join group_members m
      on m.group_id=a.group_id and m.user_id=a.user_id
      where a.task_id=src.source_group_task_id and a.user_id=p_user_id) then
      raise exception 'Group assignment changed' using errcode='23505'; end if;
    select (due_date + coalesce(due_time,'23:59:59'::time)) at time zone
      coalesce(due_timezone_name,src.timezone_name,'UTC') into group_deadline
      from group_tasks where id=src.source_group_task_id;
  end if;
  for b in select value from jsonb_array_elements(opt->'blocks') loop
    if (b->>'planned_start')::timestamptz<=clock_timestamp() then
      raise exception 'Choose a future option' using errcode='23505'; end if;
    if group_deadline is not null and (b->>'planned_start')::timestamptz +
      make_interval(mins=>(b->>'duration_minutes')::integer)>group_deadline then
      raise exception 'Group deadline changed; compare again' using errcode='23505'; end if;
    if exists(select 1 from tasks t where t.user_id=p_user_id and t.task_status<>'failed'
      and not (t.id=src.id and src.task_status='pending')
      and ((t.planned_date+t.planned_start_time::time) at time zone coalesce(t.timezone_name,'UTC'))
        < (b->>'planned_start')::timestamptz+make_interval(mins=>(b->>'duration_minutes')::integer)
      and ((t.planned_date+t.planned_start_time::time) at time zone coalesce(t.timezone_name,'UTC'))
        +make_interval(mins=>t.planned_duration_min)>(b->>'planned_start')::timestamptz) then
      raise exception 'Schedule changed; compare again' using errcode='23505'; end if;
    if idx=0 and src.task_status='pending' then
      update tasks set planned_date=(b->>'local_date')::date,
        planned_start_time=b->>'local_time', planned_duration_min=(b->>'duration_minutes')::integer,
        ai_plan_details=coalesce(src.ai_plan_details,'{}') || jsonb_build_object(
          'current_energy',c.evidence->'expected_energy','current_focus',c.evidence->'expected_focus',
          'deadline_at',b->'feature_snapshot'->'deadline_at')
        where id=src.id and user_id=p_user_id returning * into saved;
    else
      insert into tasks(user_id,title,notes,task_category,planned_date,planned_start_time,planned_duration_min,
        importance,energy_level,focus_level,total_tasks_today,task_status,timezone_name,ai_plan_details,
        source_group_task_id,group_block_key,group_source_snapshot,continuation_of_task_id)
      values(p_user_id,src.title,src.notes,src.task_category,(b->>'local_date')::date,b->>'local_time',
        (b->>'duration_minutes')::integer,src.importance,src.energy_level,src.focus_level,1,'pending',
        src.timezone_name,coalesce(src.ai_plan_details,'{}') || jsonb_build_object(
          'current_energy',c.evidence->'expected_energy','current_focus',c.evidence->'expected_focus',
          'deadline_at',b->'feature_snapshot'->'deadline_at'),
        src.source_group_task_id,gen_random_uuid(),src.group_source_snapshot,src.id)
      returning * into saved;
    end if;
    result=result || jsonb_build_array(to_jsonb(saved));
    snaps=snaps || jsonb_build_array(jsonb_build_object('task_id',saved.id,'plan_input_id',saved.ai_plan_input_id,
      'probability',b->'success_probability','feature_snapshot',b->'feature_snapshot',
      'prediction_snapshot',b->'prediction_snapshot'));
    idx=idx+1;
  end loop;
  update planning_comparisons set selected_option_id=p_option_id,selected_at=clock_timestamp(),
    applied_tasks=result,applied_snapshots=snaps where id=c.id;
  return result;
end $$;
revoke all on function public.apply_planning_option(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.apply_planning_option(uuid,uuid,text) to service_role;
commit;
