-- ============================================================
-- HabitTrace — Supabase Database Schema
-- Run this in: Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- ── Profiles (extends auth.users) ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id            UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  display_name  TEXT,
  productivity_type TEXT,     -- 'student' | 'professional' | 'freelance' | etc.
  wake_time     TEXT,         -- e.g. "07:00"
  sleep_time    TEXT,         -- e.g. "23:00"
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: user owns own row"
  ON profiles FOR ALL
  USING (auth.uid() = id);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'first_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO UPDATE
  SET display_name = EXCLUDED.display_name;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT OR UPDATE OF raw_user_meta_data ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── Tasks ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tasks (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id             UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  title               TEXT NOT NULL,
  task_category       TEXT NOT NULL,
  planned_start_time  TEXT NOT NULL,           -- "2:00 PM"
  planned_date        DATE NOT NULL DEFAULT CURRENT_DATE,
  planned_duration_min INTEGER NOT NULL CHECK (planned_duration_min > 0),
  importance          INTEGER CHECK (importance BETWEEN 1 AND 5),
  energy_level        INTEGER CHECK (energy_level BETWEEN 1 AND 5),
  focus_level         INTEGER CHECK (focus_level BETWEEN 1 AND 5),
  total_tasks_today   INTEGER DEFAULT 1,
  task_status         TEXT DEFAULT 'pending'
                        CHECK (task_status IN ('pending', 'success', 'failed')),
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tasks: user owns own rows"
  ON tasks FOR ALL
  USING (auth.uid() = user_id);

-- Index for date-filtered queries (common in habits page)
CREATE INDEX IF NOT EXISTS idx_tasks_user_date
  ON tasks (user_id, planned_date);

-- ── Executions ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS executions (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  task_id             UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  user_id             UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  actual_start_time   TEXT,
  actual_end_time     TEXT,
  interruption_count  INTEGER DEFAULT 0,
  stopped_early       BOOLEAN DEFAULT FALSE,
  task_status         TEXT CHECK (task_status IN ('success', 'failed')),
  failure_reason      TEXT,   -- canonical label: 'low_energy' | 'start_delay' | etc.
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "executions: user owns own rows"
  ON executions FOR ALL
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_executions_user
  ON executions (user_id, created_at DESC);

-- An execution can be completed later, but a task may only have one open run.
-- This also makes repeated/concurrent mobile Start taps idempotent at the DB boundary.
CREATE UNIQUE INDEX IF NOT EXISTS idx_executions_one_active_per_task
  ON executions (task_id)
  WHERE actual_end_time IS NULL;

-- ── Predictions (optional cache) ─────────────────────────────────────────────
-- Stores the ML output so the frontend doesn't need to re-call the backend.
CREATE TABLE IF NOT EXISTS predictions (
  id                       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  task_id                  UUID REFERENCES tasks(id) ON DELETE CASCADE NOT NULL,
  user_id                  UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  success_probability      FLOAT,
  personalized             BOOLEAN DEFAULT FALSE,
  predicted_failure_reason TEXT,
  failure_probabilities    JSONB,
  top_positive_factors     JSONB,
  top_negative_factors     JSONB,
  created_at               TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE predictions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "predictions: user owns own rows"
  ON predictions FOR ALL
  USING (auth.uid() = user_id);
