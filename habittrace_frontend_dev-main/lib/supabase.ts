import { createClient, SupabaseClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

/**
 * Supabase client — only created when env vars are present.
 * All callers should handle the case where this may be a stub in demo mode.
 */
function createSupabaseClient(): SupabaseClient {
  const options = {
    auth: {
      autoRefreshToken: true,
      detectSessionInUrl: true,
      persistSession: true,
    },
  };

  if (!supabaseUrl || !supabaseAnonKey) {
    // Return a stub that throws informative errors on use
    // createClient requires a URL, so we provide a dummy one and catch errors at the call site.
    return createClient("https://placeholder.supabase.co", "placeholder-key", options);
  }
  return createClient(supabaseUrl, supabaseAnonKey, options);
}

export const supabase = createSupabaseClient();
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);
