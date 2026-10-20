-- Apply to the PRIMARY Supabase project after coach_agent_schema.sql.
-- Existing message text, ownership constraints, and RLS policies remain in place.
begin;
alter table public.coach_messages
  add column if not exists metadata jsonb not null default '{}'::jsonb;
commit;
