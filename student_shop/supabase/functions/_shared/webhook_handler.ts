/**
 * Server side logic of the `xendit-webhook` edge function.
 *
 * Xendit calls this endpoint server to server. It does not send a Supabase
 * JWT, therefore the platform level JWT verification is disabled for this
 * function and the `x-callback-token` header is validated instead. Without
 * that token anybody could mark an order as PAID.
 */
import { errorResponse, handlePreflight, jsonResponse, readJsonBody } from "./http.ts";
import {
  classifyInvoiceStatus,
  isValidCallbackToken,
  normalizeInvoiceEvent,
  type NormalizedInvoiceEvent,
} from "./validation.ts";

/** Result of applying an event to the database. */
export interface WebhookApplyResult {
  result: string;
  orderId?: string | null;
  orderStatus?: string | null;
}

export interface WebhookDeps {
  /** The `XENDIT_WEBHOOK_TOKEN` secret configured in the Xendit dashboard. */
  expectedToken: string | null | undefined;
  /** Applies the event to the database (atomic + idempotent). */
  applyEvent: (event: NormalizedInvoiceEvent) => Promise<WebhookApplyResult>;
  logger?: (message: string) => void;
}

/** Builds the `xendit-webhook` request handler. */
export function createWebhookHandler(deps: WebhookDeps) {
  return async function handleWebhook(request: Request): Promise<Response> {
    const preflight = handlePreflight(request);
    if (preflight) return preflight;

    if (request.method !== "POST") {
      return errorResponse(405, "METHOD_NOT_ALLOWED", "Only POST is supported.");
    }

    // 1. Authenticate the sender.
    const providedToken = request.headers.get("x-callback-token");
    if (!isValidCallbackToken(providedToken, deps.expectedToken)) {
      deps.logger?.("rejected webhook: invalid or missing x-callback-token");
      return errorResponse(
        401,
        "INVALID_CALLBACK_TOKEN",
        "The x-callback-token header is missing or does not match the configured webhook token.",
      );
    }

    // 2. Validate the payload.
    const rawBody = await readJsonBody(request);
    if (rawBody === null) {
      return errorResponse(400, "INVALID_JSON", "The webhook body must be valid JSON.");
    }

    const normalized = normalizeInvoiceEvent(rawBody);
    if (!normalized.ok) {
      return errorResponse(400, normalized.code, normalized.message);
    }
    const event = normalized.value;

    // 3. Only paid / expired / pending invoices are interesting.
    const kind = classifyInvoiceStatus(event.status);
    if (kind === "unknown") {
      deps.logger?.(`ignoring webhook with unsupported status: ${String(event.status)}`);
      return jsonResponse({ received: true, result: "ignored_status" }, 200);
    }

    // 4. Apply the event (transactional + idempotent).
    try {
      const applied = await deps.applyEvent(event);
      return jsonResponse(
        {
          received: true,
          result: applied.result,
          order_id: applied.orderId ?? null,
          order_status: applied.orderStatus ?? null,
        },
        200,
      );
    } catch (error) {
      deps.logger?.(`failed to apply webhook event: ${String(error)}`);
      // 5xx -> Xendit retries the delivery.
      return errorResponse(
        500,
        "WEBHOOK_PROCESSING_FAILED",
        "The webhook could not be processed.",
      );
    }
  };
}
