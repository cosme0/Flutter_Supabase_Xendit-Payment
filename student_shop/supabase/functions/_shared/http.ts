import { corsHeaders } from "./cors.ts";

/** JSON response with the shared CORS headers. */
export function jsonResponse(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      ...extraHeaders,
    },
  });
}

/** Error response using the `{ error, code, message }` shape. */
export function errorResponse(
  status: number,
  code: string,
  message: string,
  extra: Record<string, unknown> = {},
): Response {
  return jsonResponse({ error: true, code, message, ...extra }, status);
}

/** Answers a CORS preflight request (returns null when it is not one). */
export function handlePreflight(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

/** Reads and parses a JSON body. Returns null when the body is not valid JSON. */
export async function readJsonBody(request: Request): Promise<unknown | null> {
  try {
    const text = await request.text();
    if (!text) return null;
    return JSON.parse(text);
  } catch {
    return null;
  }
}
