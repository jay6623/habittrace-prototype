"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import { syncProfileDisplayName } from "@/lib/profile";
import { notifyDataChanged } from "@/lib/refresh";

interface AuthContextType {
  user: User | null;
  session: Session | null;
  loading: boolean;
  displayName: string;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  session: null,
  loading: true,
  displayName: "",
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;

    // A refresh token can become invalid after changing Supabase projects,
    // clearing server-side sessions, or leaving a development tab open for a
    // long time. Recover by removing only the local session so the login page
    // can be shown instead of surfacing the raw Supabase error.
    void supabase.auth
      .getSession()
      .then(async ({ data: { session }, error }) => {
        if (error) {
          await supabase.auth.signOut({ scope: "local" });
          if (!active) return;
          setSession(null);
          setUser(null);
          return;
        }
        if (!active) return;
        setSession(session);
        setUser(session?.user ?? null);
      })
      .catch(async () => {
        await supabase.auth.signOut({ scope: "local" });
        if (!active) return;
        setSession(null);
        setUser(null);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    // Watch for sign-in and sign-out changes.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);
      }
    );

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);

  const authDisplayName = user?.user_metadata?.first_name;
  useEffect(() => {
    if (!user || typeof authDisplayName !== "string" || !authDisplayName.trim())
      return;
    let active = true;
    void syncProfileDisplayName(user.id, authDisplayName)
      .then(() => {
        if (active) notifyDataChanged();
      })
      .catch((error) => {
        console.warn("Could not synchronize the public profile name:", error);
      });
    return () => {
      active = false;
    };
  }, [authDisplayName, user]);

  // Resolve the user's display name.
  const displayName =
    user?.user_metadata?.first_name ||
    user?.email?.split("@")[0] ||
    "there";

  return (
    <AuthContext.Provider value={{ user, session, loading, displayName }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
