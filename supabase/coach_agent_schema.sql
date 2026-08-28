-- HabitTrace database-backed AI coach
-- Run this once in the PRIMARY Supabase project's SQL Editor.

begin;

create table if not exists public.coach_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'AI coaching conversation',
  status text not null default 'active'
    check (status in ('active', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index if not exists idx_coach_conversations_user_updated
  on public.coach_conversations(user_id, updated_at desc);

alter table public.coach_conversations enable row level security;
drop policy if exists "coach conversations: user owns rows"
  on public.coach_conversations;
create policy "coach conversations: user owns rows"
  on public.coach_conversations for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.coach_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 20000),
  created_at timestamptz not null default now(),
  foreign key (conversation_id, user_id)
    references public.coach_conversations(id, user_id) on delete cascade
);

create index if not exists idx_coach_messages_conversation_created
  on public.coach_messages(conversation_id, created_at);

alter table public.coach_messages enable row level security;
drop policy if exists "coach messages: user owns rows"
  on public.coach_messages;
create policy "coach messages: user owns rows"
  on public.coach_messages for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.user_coaching_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  timezone_name text not null default 'UTC',
  preferred_day_start time not null default '08:00',
  preferred_day_end time not null default '22:00',
  minimum_buffer_minutes integer not null default 15
    check (minimum_buffer_minutes between 0 and 240),
  coaching_style text not null default 'supportive'
    check (coaching_style in ('supportive', 'direct', 'analytical')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (preferred_day_start < preferred_day_end)
);

alter table public.user_coaching_preferences enable row level security;
drop policy if exists "coaching preferences: user owns row"
  on public.user_coaching_preferences;
create policy "coaching preferences: user owns row"
  on public.user_coaching_preferences for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.agent_action_proposals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_id uuid,
  action_type text not null check (action_type in ('create_task')),
  payload jsonb not null,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'dismissed', 'expired')),
  result jsonb,
  expires_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (conversation_id, user_id)
    references public.coach_conversations(id, user_id) on delete cascade
);

create index if not exists idx_agent_proposals_user_status
  on public.agent_action_proposals(user_id, status, created_at desc);

alter table public.agent_action_proposals enable row level security;
drop policy if exists "agent proposals: user owns rows"
  on public.agent_action_proposals;
create policy "agent proposals: user owns rows"
  on public.agent_action_proposals for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

commit;
