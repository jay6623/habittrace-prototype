-- Add an "admin" tier between owner and member for group scheduling.
-- Run in the PRIMARY Supabase project's SQL Editor, after group_scheduling_schema.sql.

alter table public.group_members
  drop constraint if exists group_members_role_check;

alter table public.group_members
  add constraint group_members_role_check check (role in ('owner', 'admin', 'member'));
