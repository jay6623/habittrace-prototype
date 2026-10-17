-- Individual completion for each person assigned to a group task.
-- Run once in the PRIMARY Supabase project, after group_scheduling_schema.sql.

begin;

alter table public.group_task_assignees
  add column if not exists outcome text;

alter table public.group_task_assignees
  add column if not exists logged_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'group_task_assignees_outcome_check'
      and conrelid = 'public.group_task_assignees'::regclass
  ) then
    alter table public.group_task_assignees
      add constraint group_task_assignees_outcome_check
      check (outcome is null or outcome in ('success', 'failed'));
  end if;
end $$;

commit;
