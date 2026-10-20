/**
 * Pure validation / conversion helpers.
 *
 * Everything in this file is side effect free so that it can be unit tested
 * with `deno test` without touching Supabase or Xendit.
 */

export const MIN_QUANTITY = 1;
export const MAX_QUANTITY = 10;

/** A validated checkout request coming from the Flutter app. */
export interface CheckoutRequest {
  /** UUID of the product that should be bought. */
  productId: string;
  /** How many pieces the customer wants. */
  quantity: number;
  /** Raw guest token (only used for guest checkout). */
  guestToken?: string;
  /** Client generated key used to make retries idempotent. */
  idempotencyKey?: string;
  /** Optional payer e-mail forwarded to Xendit. */
  payerEmail?: string;
}

export type ParseResult<T> =
  | { ok: true; value: T }
  | { ok: false; code: string; message: string };

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** True when the value looks like a UUID. */
export function isUuid(value: unknown): boolean {
  return typeof value === "string" && UUID_PATTERN.test(value.trim());
}

/** True when the value is a non empty opaque token of at least 32 characters. */
export function isGuestToken(value: unknown): boolean {
  return typeof value === "string" && value.trim().length >= 32;
}

/**
 * Validates the body of a `create-invoice` request.
 *
 * The client is only allowed to send a product id and a quantity - never a
 * price. Prices are always read from the database by the edge function.
 */
export function parseCheckoutRequest(payload: unknown): ParseResult<CheckoutRequest> {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return {
      ok: false,
      code: "INVALID_BODY",
      message: "The request body must be a JSON object.",
    };
  }

  const body = payload as Record<string, unknown>;

  const productId = body["product_id"] ?? body["productId"];
  if (!isUuid(productId)) {
    return {
      ok: false,
      code: "INVALID_PRODUCT_ID",
      message: "A valid product_id (uuid) is required.",
    };
  }

  // `quantity` is optional and defaults to 1, but an explicit null or an
  // unparsable value is a client error.
  const hasQuantity = Object.prototype.hasOwnProperty.call(body, "quantity") &&
    body["quantity"] !== undefined;
  const rawQuantity = hasQuantity ? body["quantity"] : 1;
  const quantity = typeof rawQuantity === "string" ? Number(rawQuantity) : rawQuantity;
  if (
    typeof quantity !== "number" ||
    !Number.isFinite(quantity) ||
    !Number.isInteger(quantity) ||
    quantity < MIN_QUANTITY ||
    quantity > MAX_QUANTITY
  ) {
    return {
      ok: false,
      code: "INVALID_QUANTITY",
      message: `quantity must be an integer between ${MIN_QUANTITY} and ${MAX_QUANTITY}.`,
    };
  }

  const guestToken = body["guest_token"] ?? body["guestToken"];
  if (guestToken !== undefined && guestToken !== null && !isGuestToken(guestToken)) {
    return {
      ok: false,
      code: "INVALID_GUEST_TOKEN",
      message: "The guest token must be at least 32 characters long.",
    };
  }

  const idempotencyKey = body["idempotency_key"] ?? body["idempotencyKey"];
  if (idempotencyKey !== undefined && idempotencyKey !== null && typeof idempotencyKey !== "string") {
    return {
      ok: false,
      code: "INVALID_IDEMPOTENCY_KEY",
      message: "idempotency_key must be a string.",
    };
  }

  const payerEmail = body["payer_email"] ?? body["payerEmail"];
  if (payerEmail !== undefined && payerEmail !== null && typeof payerEmail !== "string") {
    return {
      ok: false,
      code: "INVALID_PAYER_EMAIL",
      message: "payer_email must be a string.",
    };
  }

  return {
    ok: true,
    value: {
      productId: (productId as string).trim(),
      quantity,
      guestToken: typeof guestToken === "string" ? guestToken.trim() : undefined,
      idempotencyKey: typeof idempotencyKey === "string" ? idempotencyKey.trim() : undefined,
      payerEmail: typeof payerEmail === "string" && payerEmail.includes("@")
        ? payerEmail.trim()
        : undefined,
    },
  };
}

/**
 * Converts a peso amount into the minor units used by Xendit.
 * PHP 1,500.00 -> 150000 (centavos).
 */
export function toMinorUnits(phpAmount: number): number {
  return Math.round(phpAmount * 100);
}

/** Converts Xendit minor units back into pesos. */
export function fromMinorUnits(minorUnits: number): number {
  return Math.round(minorUnits) / 100;
}

/**
 * Constant time comparison of the Xendit callback token.
 *
 * The webhook endpoint is public (JWT verification is disabled because
 * Xendit does not send a Supabase JWT), therefore validating the
 * `x-callback-token` header is the only thing that stops an attacker from
 * marking arbitrary orders as PAID.
 */
export function isValidCallbackToken(
  provided: string | null | undefined,
  expected: string | null | undefined,
): boolean {
  if (typeof provided !== "string" || typeof expected !== "string") return false;
  if (expected.length === 0 || provided.length !== expected.length) return false;

  let mismatch = 0;
  for (let i = 0; i < expected.length; i += 1) {
    mismatch |= provided.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return mismatch === 0;
}

/** The kind of event a Xendit invoice status represents. */
export type XenditEventKind = "paid" | "expired" | "pending" | "unknown";

/**
 * Maps the `status` field of an Xendit invoice payload to an event kind.
 *   PENDING  -> the customer has not paid yet
 *   PAID     -> the money arrived
 *   SETTLED  -> the money arrived and was settled (treated like PAID)
 *   EXPIRED  -> the invoice timed out
 */
export function classifyInvoiceStatus(status: unknown): XenditEventKind {
  if (typeof status !== "string") return "unknown";
  switch (status.trim().toUpperCase()) {
    case "PAID":
    case "SETTLED":
      return "paid";
    case "EXPIRED":
      return "expired";
    case "PENDING":
      return "pending";
    default:
      return "unknown";
  }
}

/**
 * Supabase sends the project key (and not a user session) when no user is
 * signed in. Such a token identifies the application and must not be treated
 * as an invalid user session - otherwise the guest checkout would be
 * rejected.
 */
export function isApplicationKey(token: string, applicationKeys: string[]): boolean {
  if (!token) return false;
  return applicationKeys.some(
    (key) => typeof key === "string" && key.length > 0 && key === token,
  );
}

/**
 * Builds a stable key for a webhook delivery. Xendit retries deliveries, so
 * the same event has to produce the same key to stay idempotent.
 */
export function buildEventKey(
  invoiceId: string | null,
  status: string | null,
  paidAt: string | null,
): string {
  return `${invoiceId ?? "no-invoice"}|${(status ?? "UNKNOWN").toUpperCase()}|${paidAt ?? ""}`;
}

/** Normalised view of an Xendit invoice webhook payload. */
export interface NormalizedInvoiceEvent {
  invoiceId: string | null;
  externalId: string | null;
  status: string | null;
  amount: number | null;
  currency: string | null;
  paidAt: string | null;
  paymentMethod: string | null;
  eventKey: string;
}

/** Converts a raw webhook body into a normalised invoice event. */
export function normalizeInvoiceEvent(payload: unknown): ParseResult<NormalizedInvoiceEvent> {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return {
      ok: false,
      code: "INVALID_PAYLOAD",
      message: "The webhook payload must be a JSON object.",
    };
  }

  const body = payload as Record<string, unknown>;
  const invoiceId = typeof body["id"] === "string" ? body["id"] : null;
  const externalId = typeof body["external_id"] === "string" ? body["external_id"] : null;

  if (!invoiceId && !externalId) {
    return {
      ok: false,
      code: "INVALID_PAYLOAD",
      message: "The webhook payload must contain an invoice id.",
    };
  }

  const status = typeof body["status"] === "string" ? body["status"] : null;
  const rawAmount = body["amount"];
  const amount = typeof rawAmount === "number" && Number.isFinite(rawAmount) ? rawAmount : null;
  const currency = typeof body["currency"] === "string" ? body["currency"] : null;
  const paidAt = typeof body["paid_at"] === "string" ? body["paid_at"] : null;
  const paymentMethod = typeof body["payment_method"] === "string" ? body["payment_method"] : null;

  return {
    ok: true,
    value: {
      invoiceId,
      externalId,
      status,
      amount,
      currency,
      paidAt,
      paymentMethod,
      eventKey: buildEventKey(invoiceId, status, paidAt),
    },
  };
}
