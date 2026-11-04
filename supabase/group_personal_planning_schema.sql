-- PRIMARY project, after group_scheduling_schema.sql and task_ai_sync_schema.sql.
begin;

alter table public.group_tasks
  add column if not exists estimated_duration_minutes integer
    check (estimated_duration_minutes between 1 and 720),
  add column if not exists due_timezone_name text;

-- Private links live on user-owned tasks, never on shared group responses.
-- Deleting the group task preserves the user's plan and execution history.
alter table public.tasks
  add column if not exists source_group_task_id uuid
    references public.group_tasks(id) on delete set null;

create unique index if not exists idx_tasks_user_source_group_task
  on public.tasks(user_id, source_group_task_id)
  where source_group_task_id is not null;

-- Existing task ownership RLS applies. Validate links even on direct browser writes.
create or replace function public.validate_personal_group_task_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.source_group_task_id is null then return new; end if;
  if tg_op = 'UPDATE' then
    if new.source_group_task_id is not distinct from old.source_group_task_id
       and new.user_id is not distinct from old.user_id then return new; end if;
  end if;
  if not exists (
    select 1 from public.group_task_assignees a
    join public.group_members m on m.group_id = a.group_id and m.user_id = a.user_id
    where a.task_id = new.source_group_task_id and a.user_id = new.user_id
  ) then
    raise exception 'Only current assigned group members can link a personal plan'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_personal_group_task_link on public.tasks;
create trigger validate_personal_group_task_link
before insert or update of source_group_task_id, user_id on public.tasks
for each row execute function public.validate_personal_group_task_link();

commit;
