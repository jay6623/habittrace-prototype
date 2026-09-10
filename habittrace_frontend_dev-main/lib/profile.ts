import { supabase } from "./supabase";

/** Keep the public profile used by Groups aligned with Supabase Auth metadata. */
export async function syncProfileDisplayName(
  userId: string,
  displayName: string,
): Promise<void> {
  const normalized = displayName.trim();
  if (!normalized) throw new Error("Display name is required.");

  const { error } = await supabase.from("profiles").upsert(
    {
      id: userId,
      display_name: normalized,
    },
    { onConflict: "id" },
  );
  if (error) throw error;
}
