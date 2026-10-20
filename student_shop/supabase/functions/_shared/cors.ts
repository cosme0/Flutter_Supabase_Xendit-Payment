/**
 * Shared CORS configuration for the student_shop edge functions.
 *
 * The Flutter client runs on a device (no browser origin), so the CORS
 * headers only matter for local web debugging. The important part is that
 * `x-guest-token` and `idempotency-key` are allowed request headers.
 */
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-guest-token, idempotency-key",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Max-Age": "86400",
};
