/**
 * Helpers around the Supabase client that are shared by the edge functions.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

/**
 * PostgREST returns a single row either as an object or as an array with one
 * element (depending on the return type of the RPC). This helper always
 * returns the first row or null.
 */
export function firstRow<T>(data: unknown): T | null {
  if (data === null || data === undefined) return null;
  if (Array.isArray(data)) {
    return data.length > 0 ? (data[0] as T) : null;
  }
  if (typeof data === "object") return data as T;
  return null;
}

/** Reads the service role key from the environment (new and legacy names). */
export function readServiceRoleKey(): string {
  return Deno.env.get("SUPABASE_SECRET_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    "";
}

/** Reads the project url from the environment. */
export function readSupabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

/** Builds a service role client (bypasses RLS - server side only!). */
export function createAdminClient(url: string, serviceRoleKey: string): SupabaseClient {
  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
