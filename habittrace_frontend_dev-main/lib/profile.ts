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

/** Keep Groups member avatars aligned with the signed-in user's photo. */
export async function syncProfileAvatar(
  userId: string,
  avatarUrl: string | null,
): Promise<void> {
  const normalized =
    typeof avatarUrl === "string" && avatarUrl.trim() ? avatarUrl.trim() : null;

  const { error } = await supabase.from("profiles").upsert(
    {
      id: userId,
      avatar_url: normalized,
    },
    { onConflict: "id" },
  );
  if (error) throw error;
}
