-- HabitTrace group scheduling (GitHub issue #6)
-- Run this once in the PRIMARY Supabase project's SQL Editor, after schema.sql.

begin;

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  invite_code text not null unique check (invite_code ~ '^[A-Z0-9]{8}$'),
  created_at timestamptz not null default now()
);

create index if not exists idx_groups_owner on public.groups(owner_id);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists idx_group_members_user on public.group_members(user_id);

create table if not exists public.group_tasks (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  assigned_to uuid references auth.users(id) on delete set null,
  title text not null check (char_length(title) between 1 and 200),
  category text not null default 'Other' check (char_length(category) between 1 and 40),
  priority text not null default 'medium' check (priority in ('high', 'medium', 'low')),
  status text not null default 'pending' check (status in ('pending', 'success', 'failed')),
  due_date date,
  due_time time,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_group_tasks_group_created
  on public.group_tasks(group_id, created_at desc);

-- A task can be assigned to multiple current group members. Keep the legacy
-- group_tasks.assigned_to column during migration for older clients.
create table if not exists public.group_task_assignees (
  group_id uuid not null,
  task_id uuid not null references public.group_tasks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_at timestamptz not null default now(),
  primary key (task_id, user_id),
  foreign key (group_id, user_id)
    references public.group_members(group_id, user_id) on delete cascade
);

create index if not exists idx_group_task_assignees_group_user
  on public.group_task_assignees(group_id, user_id);

insert into public.group_task_assignees (group_id, task_id, user_id)
select group_id, id, assigned_to
from public.group_tasks
where assigned_to is not null
on conflict (task_id, user_id) do nothing;

-- Backend-only tables. The FastAPI service-role client enforces group
-- membership on every read and write, so RLS is enabled with no policies:
-- direct anon/authenticated access is denied entirely.
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_tasks enable row level security;
alter table public.group_task_assignees enable row level security;

commit;
