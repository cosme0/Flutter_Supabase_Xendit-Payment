/**
 * SHA-256 helpers so that the edge functions can hash guest tokens exactly
 * the same way as PostgreSQL does:
 *
 *   encode(digest(token, 'sha256'), 'hex')
 */
export async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
