/**
 * Public site origin for OAuth redirects (`redirectTo`). Prefer NEXT_PUBLIC_SITE_URL in
 * production when the canonical URL must match Supabase “Redirect URLs” exactly.
 */
export function getOAuthRedirectBaseUrl(): string {
  const explicit = process.env.NEXT_PUBLIC_SITE_URL?.trim().replace(/\/+$/, "");
  if (explicit) return explicit;
  if (typeof window !== "undefined") return window.location.origin;
  return "";
}
