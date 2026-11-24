-- PRIMARY project, after group_personal_planning_schema.sql and group_task_completion_schema.sql.
begin;

-- Stable per-block retry keys preserve the initial block and allow explicit splits.
alter table public.tasks
  add column if not exists group_block_key uuid not null default '00000000-0000-4000-8000-000000000001',
  add column if not exists group_source_snapshot jsonb not null default '{}';

drop index if exists public.idx_tasks_user_source_group_task;
create unique index if not exists idx_tasks_user_source_group_block
  on public.tasks(user_id, source_group_task_id, group_block_key)
  where source_group_task_id is not null;

-- Private prediction inputs never live on shared assignments.
alter table public.group_task_assignees
  add column if not exists shared_progress text
    check (shared_progress is null or shared_progress in ('planned', 'in_progress', 'needs_help'));

-- Group tables retain RLS without browser policies. The authenticated API
-- verifies current membership and assignment and only changes the caller's row.
commit;
