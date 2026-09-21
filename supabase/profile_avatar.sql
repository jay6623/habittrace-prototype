-- Add public avatar URL used by Groups member cards.
-- Run in the PRIMARY Supabase project's SQL Editor.

alter table public.profiles
  add column if not exists avatar_url text;
