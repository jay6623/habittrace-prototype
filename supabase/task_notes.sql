-- Add optional plan notes (run in Supabase SQL Editor if tasks already exist).
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS notes TEXT;

COMMENT ON COLUMN tasks.notes IS 'Optional user note shown with the plan';
