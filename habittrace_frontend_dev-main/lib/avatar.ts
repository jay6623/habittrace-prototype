import { User } from "@supabase/supabase-js";
import { syncProfileAvatar } from "./profile";
import { supabase } from "./supabase";

const MAX_EDGE = 256;
const MAX_DATA_URL_CHARS = 90_000;

/** Prefer custom upload, then Google OAuth picture. */
export function readAvatarUrl(
  user: User | null | undefined,
): string | null {
  if (!user) return null;
  const meta = user.user_metadata ?? {};
  const custom = meta.avatar_url;
  const picture = meta.picture;
  if (typeof custom === "string" && custom.trim()) return custom.trim();
  if (typeof picture === "string" && picture.trim()) return picture.trim();
  return null;
}

export function avatarInitials(displayName: string, email?: string | null): string {
  const source = displayName.trim() || email?.trim() || "?";
  const parts = source.split(/\s+/).filter(Boolean);
  if (parts.length >= 2) {
    return `${parts[0]![0] ?? ""}${parts[1]![0] ?? ""}`.toUpperCase();
  }
  return source.slice(0, 2).toUpperCase();
}

/** Resize/compress an image file for avatar use. */
export async function fileToAvatarDataUrl(file: File): Promise<string> {
  if (!file.type.startsWith("image/")) {
    throw new Error("Choose an image file.");
  }
  if (file.size > 8 * 1024 * 1024) {
    throw new Error("Keep the image under 8 MB.");
  }

  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) {
    bitmap.close();
    throw new Error("Couldn’t process that image.");
  }
  context.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  let quality = 0.86;
  let dataUrl = canvas.toDataURL("image/jpeg", quality);
  while (dataUrl.length > MAX_DATA_URL_CHARS && quality > 0.45) {
    quality -= 0.08;
    dataUrl = canvas.toDataURL("image/jpeg", quality);
  }
  if (dataUrl.length > MAX_DATA_URL_CHARS) {
    throw new Error("That image is still too large after compression. Try another photo.");
  }
  return dataUrl;
}

/**
 * Persist avatar on the auth user. Tries Supabase Storage first; falls back to a
 * compressed data URL in user metadata when the bucket is unavailable.
 */
export async function uploadUserAvatar(userId: string, file: File): Promise<string> {
  const dataUrl = await fileToAvatarDataUrl(file);
  const blob = await (await fetch(dataUrl)).blob();
  const path = `${userId}/avatar.jpg`;

  const { error: uploadError } = await supabase.storage
    .from("avatars")
    .upload(path, blob, { upsert: true, contentType: "image/jpeg" });

  let avatarUrl = dataUrl;
  if (!uploadError) {
    const { data } = supabase.storage.from("avatars").getPublicUrl(path);
    avatarUrl = `${data.publicUrl}?v=${Date.now()}`;
  }

  const { error } = await supabase.auth.updateUser({
    data: { avatar_url: avatarUrl },
  });
  if (error) throw error;

  await syncProfileAvatar(userId, avatarUrl);
  return avatarUrl;
}

/** Clear custom avatar so the UI falls back to Google picture or initials. */
export async function clearUserAvatar(userId: string): Promise<void> {
  const path = `${userId}/avatar.jpg`;
  await supabase.storage.from("avatars").remove([path]).catch(() => undefined);

  const { error } = await supabase.auth.updateUser({
    data: { avatar_url: "" },
  });
  if (error) throw error;

  const { data } = await supabase.auth.getUser();
  const fallback = readAvatarUrl(data.user);
  await syncProfileAvatar(userId, fallback);
}
