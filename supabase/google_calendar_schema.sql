-- HabitTrace Google Calendar integration (primary Supabase project).
-- Run in Supabase Dashboard -> SQL Editor before enabling the integration.

CREATE TABLE IF NOT EXISTS calendar_connections (
  id                       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id                  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  provider                 TEXT NOT NULL DEFAULT 'google' CHECK (provider = 'google'),
  calendar_id              TEXT NOT NULL DEFAULT 'primary',
  timezone                 TEXT NOT NULL DEFAULT 'UTC',
  access_token_encrypted   TEXT NOT NULL,
  refresh_token_encrypted  TEXT NOT NULL,
  token_expires_at         TIMESTAMPTZ NOT NULL,
  last_synced_at           TIMESTAMPTZ,
  last_error               TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, provider)
);

CREATE TABLE IF NOT EXISTS calendar_event_links (
  id                 UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id            UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  task_id            UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  calendar_id        TEXT NOT NULL DEFAULT 'primary',
  google_event_id    TEXT NOT NULL,
  last_synced_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, task_id),
  UNIQUE (user_id, calendar_id, google_event_id)
);

CREATE INDEX IF NOT EXISTS idx_calendar_connections_user
  ON calendar_connections (user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_event_links_task
  ON calendar_event_links (task_id);

ALTER TABLE calendar_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_event_links ENABLE ROW LEVEL SECURITY;

-- Intentionally no browser RLS policies. These tables contain encrypted OAuth
-- credentials and are accessible only through the authenticated backend using
-- its Supabase service-role key.
