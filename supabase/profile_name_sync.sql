-- Keep the display name used by Groups aligned with Supabase Auth metadata.
-- Safe to run more than once in the primary Supabase project's SQL Editor.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(BTRIM(NEW.raw_user_meta_data->>'first_name'), ''),
      split_part(NEW.email, '@', 1)
    )
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

-- Backfill users whose Auth name and public profile became out of sync.
INSERT INTO public.profiles (id, display_name)
SELECT
  users.id,
  COALESCE(
    NULLIF(BTRIM(users.raw_user_meta_data->>'first_name'), ''),
    split_part(users.email, '@', 1)
  )
FROM auth.users AS users
ON CONFLICT (id) DO UPDATE
SET display_name = EXCLUDED.display_name;
