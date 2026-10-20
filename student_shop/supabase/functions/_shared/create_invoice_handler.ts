/**
 * Server side logic of the `create-invoice` edge function.
 *
 * The handler is written against injected dependencies so that the whole
 * business logic can be unit tested without a Supabase project:
 *
 *   deno test --allow-env supabase/functions/_shared
 */
import {
  errorResponse,
  handlePreflight,
  jsonResponse,
  readJsonBody,
} from "./http.ts";
import {
  parseCheckoutRequest,
  toMinorUnits,
  type CheckoutRequest,
} from "./validation.ts";

/** Identity of the caller (a signed in user or a guest device). */
export interface CallerIdentity {
  /** Supabase auth user id, `null` for guest checkout. */
  userId: string | null;
  /** Raw guest token, `null` for signed in users. */
  guestToken: string | null;
  /** True when the server had to issue a brand new guest token. */
  isNewGuest: boolean;
}

/** A catalogue product as seen by the server. */
export interface ProductRecord {
  id: string;
  name: string;
  /** Price in pesos (major unit). */
  price: number;
  stockQuantity: number;
  isActive: boolean;
}

/** A pending order as seen by the server. */
export interface OrderRecord {
  id: string;
  externalId: string;
  totalAmount: number;
  currency: string;
  status: string;
  xenditInvoiceId: string | null;
  xenditInvoiceUrl: string | null;
}

/** Error that carries an HTTP status and a machine readable code. */
export class CheckoutError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "CheckoutError";
    this.status = status;
    this.code = code;
  }
}

export interface CreateInvoiceDeps {
  /** Resolves the caller from the request (JWT / guest token). */
  resolveCaller: (request: Request) => Promise<CallerIdentity>;
  /** Looks up a previously created order for an idempotency key. */
  findOrderByIdempotencyKey: (
    idempotencyKey: string,
    caller: CallerIdentity,
  ) => Promise<OrderRecord | null>;
  /** Loads the authoritative product (price + stock) from the database. */
  loadProduct: (productId: string) => Promise<ProductRecord | null>;
  /** Creates the pending order and reserves the stock. */
  createOrder: (args: {
    product: ProductRecord;
    quantity: number;
    caller: CallerIdentity;
    idempotencyKey?: string;
  }) => Promise<OrderRecord>;
  /** Marks an order as failed and releases the reserved stock. */
  cancelOrder: (orderId: string, reason: string) => Promise<void>;
  /** Stores the Xendit invoice reference on the order. */
  attachInvoice: (orderId: string, invoiceId: string, invoiceUrl: string) => Promise<void>;
  /** Creates the invoice through the Xendit API. */
  createInvoice: (args: {
    externalId: string;
    productName: string;
    quantity: number;
    amountMinorUnits: number;
    currency: string;
    payerEmail?: string;
  }) => Promise<{ id: string; invoice_url: string; status?: string }>;
  /** Creates a cryptographically random guest token. */
  generateGuestToken: () => string;
  logger?: (message: string) => void;
}

const GUEST_TOKEN_BYTES = 32;

/** Creates a random guest token (64 hex characters). */
export function generateGuestToken(): string {
  const bytes = new Uint8Array(GUEST_TOKEN_BYTES);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function orderPayload(
  order: OrderRecord,
  productName?: string,
  quantity?: number,
  guestToken?: string,
  isNewGuest = false,
): Record<string, unknown> {
  return {
    order_id: order.id,
    external_id: order.externalId,
    invoice_id: order.xenditInvoiceId,
    invoice_url: order.xenditInvoiceUrl,
    status: order.status,
    ...(productName ? { product_name: productName } : {}),
    ...(quantity ? { quantity } : {}),
    amount: toMinorUnits(order.totalAmount),
    amount_display: order.totalAmount,
    currency: order.currency,
    ...(guestToken && isNewGuest ? { guest_token: guestToken } : {}),
  };
}

/**
 * Builds the `create-invoice` request handler.
 */
export function createCreateInvoiceHandler(deps: CreateInvoiceDeps) {
  return async function handleCreateInvoice(request: Request): Promise<Response> {
    const preflight = handlePreflight(request);
    if (preflight) return preflight;

    if (request.method !== "POST") {
      return errorResponse(405, "METHOD_NOT_ALLOWED", "Only POST is supported.");
    }

    const rawBody = await readJsonBody(request);
    if (rawBody === null) {
      return errorResponse(400, "INVALID_JSON", "The request body must be valid JSON.");
    }

    const parsed = parseCheckoutRequest(rawBody);
    if (!parsed.ok) {
      return errorResponse(400, parsed.code, parsed.message);
    }
    const checkout: CheckoutRequest = parsed.value;

    let caller: CallerIdentity;
    try {
      caller = await deps.resolveCaller(request);
    } catch (error) {
      const status = error instanceof CheckoutError ? error.status : 401;
      const code = error instanceof CheckoutError ? error.code : "UNAUTHORIZED";
      const message = error instanceof Error ? error.message : "Authentication failed.";
      return errorResponse(status, code, message);
    }

    // A guest that does not have a token yet receives one from the server.
    if (!caller.userId) {
      const suppliedToken = checkout.guestToken ?? caller.guestToken;
      if (suppliedToken) {
        caller = { userId: null, guestToken: suppliedToken, isNewGuest: false };
      } else {
        caller = {
          userId: null,
          guestToken: deps.generateGuestToken(),
          isNewGuest: true,
        };
      }
    }

    const idempotencyKey = checkout.idempotencyKey ??
      request.headers.get("idempotency-key") ??
      undefined;

    // Idempotency: a retried request must not create a second invoice.
    if (idempotencyKey) {
      const existing = await deps.findOrderByIdempotencyKey(idempotencyKey, caller);
      if (existing && existing.xenditInvoiceId && existing.xenditInvoiceUrl) {
        return jsonResponse(
          {
            ...orderPayload(
              existing,
              undefined,
              undefined,
              caller.guestToken ?? undefined,
              false,
            ),
            idempotent_replay: true,
          },
          200,
        );
      }
    }

    const product = await deps.loadProduct(checkout.productId);
    if (!product) {
      return errorResponse(404, "PRODUCT_NOT_FOUND", "The selected product does not exist.");
    }
    if (!product.isActive) {
      return errorResponse(
        409,
        "PRODUCT_UNAVAILABLE",
        "The selected product is not available for purchase.",
      );
    }
    if (product.stockQuantity < checkout.quantity) {
      return errorResponse(
        409,
        "OUT_OF_STOCK",
        `Only ${product.stockQuantity} piece(s) left in stock.`,
      );
    }

    let order: OrderRecord;
    try {
      order = await deps.createOrder({
        product,
        quantity: checkout.quantity,
        caller,
        idempotencyKey,
      });
    } catch (error) {
      if (error instanceof CheckoutError) {
        return errorResponse(error.status, error.code, error.message);
      }
      deps.logger?.(`create_order failed: ${String(error)}`);
      return errorResponse(500, "ORDER_CREATION_FAILED", "The order could not be created.");
    }

    // Replay of an order that already has an invoice (race / retry).
    if (order.xenditInvoiceId && order.xenditInvoiceUrl) {
      return jsonResponse(
        {
          ...orderPayload(
            order,
            product.name,
            checkout.quantity,
            caller.guestToken ?? undefined,
            caller.isNewGuest,
          ),
          idempotent_replay: true,
        },
        200,
      );
    }

    const amountMinorUnits = toMinorUnits(order.totalAmount);

    let invoice: { id: string; invoice_url: string; status?: string };
    try {
      invoice = await deps.createInvoice({
        externalId: order.externalId,
        productName: product.name,
        quantity: checkout.quantity,
        amountMinorUnits,
        currency: order.currency,
        payerEmail: checkout.payerEmail,
      });
    } catch (error) {
      deps.logger?.(`xendit invoice creation failed: ${String(error)}`);
      try {
        await deps.cancelOrder(order.id, "xendit_invoice_creation_failed");
      } catch (cancelError) {
        deps.logger?.(`cancel_order failed: ${String(cancelError)}`);
      }
      return errorResponse(
        502,
        "XENDIT_ERROR",
        "The payment provider could not be reached. Please try again.",
      );
    }

    try {
      await deps.attachInvoice(order.id, invoice.id, invoice.invoice_url);
    } catch (error) {
      deps.logger?.(`attach_invoice failed: ${String(error)}`);
    }

    order = {
      ...order,
      xenditInvoiceId: invoice.id,
      xenditInvoiceUrl: invoice.invoice_url,
    };

    return jsonResponse(
      {
        ...orderPayload(
          order,
          product.name,
          checkout.quantity,
          caller.guestToken ?? undefined,
          caller.isNewGuest,
        ),
        idempotent_replay: false,
      },
      201,
    );
  };
}
