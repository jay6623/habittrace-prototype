-- Group announcements and member replies.
-- Run this once in the PRIMARY Supabase project, after group_scheduling_schema.sql.
-- Safe to run again: it adds `title` if the table was created without one.

begin;

create table if not exists public.group_announcements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

alter table public.group_announcements
  add column if not exists title text;

update public.group_announcements
set title = left(btrim(body), 120)
where title is null or btrim(title) = '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'group_announcements_title_check'
      and conrelid = 'public.group_announcements'::regclass
  ) then
    alter table public.group_announcements
      add constraint group_announcements_title_check
      check (char_length(btrim(title)) between 1 and 120);
  end if;
end $$;

alter table public.group_announcements
  alter column title set not null;

create index if not exists idx_group_announcements_group_created
  on public.group_announcements(group_id, created_at desc);

create table if not exists public.group_announcement_replies (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.group_announcements(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists idx_group_announcement_replies_thread
  on public.group_announcement_replies(announcement_id, created_at);

-- Backend-only, same as the other group tables: RLS on, no browser policies.
alter table public.group_announcements enable row level security;
alter table public.group_announcement_replies enable row level security;

commit;
