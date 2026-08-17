/**
 * Public site origin for OAuth redirects (`redirectTo`). Prefer NEXT_PUBLIC_SITE_URL in
 * production when the canonical URL must match Supabase “Redirect URLs” exactly.
 */
export function getOAuthRedirectBaseUrl(): string {
  if (typeof window !== "undefined") {
    const origin = window.location.origin.replace(/\/+$/, "");
    if (origin.includes("localhost") || origin.includes("127.0.0.1")) {
      return origin;
    }
  }

  const explicit = process.env.NEXT_PUBLIC_SITE_URL?.trim().replace(/\/+$/, "");
  if (explicit) return explicit;
  if (typeof window !== "undefined") return window.location.origin;
  return "";
}
