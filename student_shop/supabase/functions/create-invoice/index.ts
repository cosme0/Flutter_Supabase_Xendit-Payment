/**
 * `create-invoice` edge function (Supabase project: BMC-ecom1).
 *
 * Flow
 *   1. validate the request  (product id + quantity only, never a price)
 *   2. resolve the caller    (Supabase user JWT, otherwise guest checkout)
 *   3. read price + stock    from the database (server side truth)
 *   4. create a pending order and reserve the stock
 *   5. call the Xendit invoice API with the server side secret
 *   6. store the invoice id + checkout url on the order
 *   7. return only what the app needs
 *
 * Secrets (Supabase edge function secrets, never in the Flutter app):
 *   XENDIT_SECRET_KEY
 */
import {
  CheckoutError,
  createCreateInvoiceHandler,
  generateGuestToken,
  type CallerIdentity,
  type OrderRecord,
  type ProductRecord,
} from "../_shared/create_invoice_handler.ts";
import { sha256Hex } from "../_shared/crypto.ts";
import { errorResponse } from "../_shared/http.ts";
import {
  createAdminClient,
  firstRow,
  readServiceRoleKey,
  readSupabaseUrl,
} from "../_shared/supabase_client.ts";
import { isApplicationKey } from "../_shared/validation.ts";
import { buildInvoiceRequest, createXenditInvoice } from "../_shared/xendit.ts";

const supabaseUrl = readSupabaseUrl();
const serviceRoleKey = readServiceRoleKey();
const xenditSecretKey = Deno.env.get("XENDIT_SECRET_KEY") ?? "";

/**
 * The public keys of the project. When no user is signed in the Flutter
 * client sends one of them instead of a user session - such a request is a
 * guest checkout and not an invalid session.
 */
const applicationKeys: string[] = [
  Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "",
];

/**
 * Optional list of payment channels, e.g. `GCASH,MAYA`.
 * When the secret is not set the field is omitted and Xendit shows every
 * channel that is activated for the account.
 */
const paymentMethods: string[] = (Deno.env.get("XENDIT_PAYMENT_METHODS") ?? "")
  .split(",")
  .map((value) => value.trim().toUpperCase())
  .filter((value) => value.length > 0);

const supabase = createAdminClient(supabaseUrl, serviceRoleKey);

interface OrderRow {
  id: string;
  external_id: string;
  total_amount: number | string;
  currency: string;
  status: string;
  xendit_invoice_id: string | null;
  xendit_invoice_url: string | null;
}

function toOrderRecord(row: OrderRow): OrderRecord {
  return {
    id: row.id,
    externalId: row.external_id,
    totalAmount: Number(row.total_amount),
    currency: row.currency,
    status: row.status,
    xenditInvoiceId: row.xendit_invoice_id,
    xenditInvoiceUrl: row.xendit_invoice_url,
  };
}

/**
 * Resolves the caller.
 *
 * When an `Authorization: Bearer <jwt>` header is present the JWT is verified
 * server side against Supabase Auth. An invalid token is rejected - it is
 * never silently downgraded to a guest order. The public project key is not a
 * user session though, it identifies the application and therefore starts a
 * guest checkout.
 */
async function resolveCaller(request: Request): Promise<CallerIdentity> {
  const authHeader = request.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";

  if (token && !isApplicationKey(token, applicationKeys)) {
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data.user) {
      throw new CheckoutError(
        401,
        "INVALID_TOKEN",
        "The access token is invalid or has expired. Please sign in again.",
      );
    }
    return { userId: data.user.id, guestToken: null, isNewGuest: false };
  }

  const headerToken = request.headers.get("x-guest-token");
  if (headerToken && headerToken.trim().length >= 32) {
    return { userId: null, guestToken: headerToken.trim(), isNewGuest: false };
  }

  return { userId: null, guestToken: null, isNewGuest: true };
}

/** Looks up an order that was created with the same idempotency key. */
async function findOrderByIdempotencyKey(
  idempotencyKey: string,
  caller: CallerIdentity,
): Promise<OrderRecord | null> {
  let query = supabase
    .from("orders")
    .select(
      "id, external_id, total_amount, currency, status, xendit_invoice_id, xendit_invoice_url",
    )
    .eq("idempotency_key", idempotencyKey);

  if (caller.userId) {
    query = query.eq("user_id", caller.userId);
  } else if (caller.guestToken) {
    query = query.eq("guest_token_hash", await sha256Hex(caller.guestToken));
  } else {
    return null;
  }

  const { data, error } = await query.limit(1);
  if (error) {
    console.error("findOrderByIdempotencyKey failed:", error.message);
    return null;
  }
  const row = firstRow<OrderRow>(data);
  return row ? toOrderRecord(row) : null;
}

/** Loads the authoritative product (price + stock) from the database. */
async function loadProduct(productId: string): Promise<ProductRecord | null> {
  const { data, error } = await supabase
    .from("products")
    .select("id, name, price, stock_quantity, is_active")
    .eq("id", productId)
    .maybeSingle();

  if (error) {
    console.error("loadProduct failed:", error.message);
    return null;
  }
  if (!data) return null;

  return {
    id: data.id as string,
    name: data.name as string,
    price: Number(data.price),
    stockQuantity: Number(data.stock_quantity ?? 0),
    isActive: data.is_active === true,
  };
}

/** Creates the pending order (server side price calculation). */
async function createOrder(args: {
  product: ProductRecord;
  quantity: number;
  caller: CallerIdentity;
  idempotencyKey?: string;
}): Promise<OrderRecord> {
  const { data, error } = await supabase.rpc("create_order", {
    p_product_id: args.product.id,
    p_quantity: args.quantity,
    p_user_id: args.caller.userId,
    p_guest_token: args.caller.guestToken,
    p_idempotency_key: args.idempotencyKey ?? null,
    p_external_id: null,
  });

  if (error) {
    const message = error.message ?? "";
    if (message.includes("OUT_OF_STOCK")) {
      throw new CheckoutError(409, "OUT_OF_STOCK", "Not enough items in stock.");
    }
    if (message.includes("PRODUCT_UNAVAILABLE")) {
      throw new CheckoutError(
        409,
        "PRODUCT_UNAVAILABLE",
        "The selected product is not available for purchase.",
      );
    }
    if (message.includes("PRODUCT_NOT_FOUND")) {
      throw new CheckoutError(404, "PRODUCT_NOT_FOUND", "The selected product does not exist.");
    }
    if (message.includes("INVALID_QUANTITY")) {
      throw new CheckoutError(400, "INVALID_QUANTITY", "The quantity is not valid.");
    }
    if (message.includes("INVALID_GUEST_TOKEN")) {
      throw new CheckoutError(400, "INVALID_GUEST_TOKEN", "The guest token is not valid.");
    }
    console.error("create_order failed:", message);
    throw new CheckoutError(500, "ORDER_CREATION_FAILED", "The order could not be created.");
  }

  const row = firstRow<OrderRow>(data);
  if (!row) {
    throw new CheckoutError(500, "ORDER_CREATION_FAILED", "The order could not be created.");
  }
  return toOrderRecord(row);
}

/** Marks the order as failed and releases the reserved stock. */
async function cancelOrder(orderId: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc("cancel_order", {
    p_order_id: orderId,
    p_reason: reason,
  });
  if (error) console.error("cancel_order failed:", error.message);
}

/** Stores the Xendit invoice reference on the order. */
async function attachInvoice(
  orderId: string,
  invoiceId: string,
  invoiceUrl: string,
): Promise<void> {
  const { error } = await supabase
    .from("orders")
    .update({
      xendit_invoice_id: invoiceId,
      xendit_invoice_url: invoiceUrl,
      updated_at: new Date().toISOString(),
    })
    .eq("id", orderId);
  if (error) console.error("attachInvoice failed:", error.message);
}

/** Calls the Xendit invoice API. */
async function createInvoice(args: {
  externalId: string;
  productName: string;
  quantity: number;
  amountMinorUnits: number;
  currency: string;
  payerEmail?: string;
}): Promise<{ id: string; invoice_url: string; status?: string }> {
  const payload = buildInvoiceRequest({
    externalId: args.externalId,
    productName: args.productName,
    quantity: args.quantity,
    amountMinorUnits: args.amountMinorUnits,
    currency: args.currency,
    payerEmail: args.payerEmail,
    paymentMethods,
  });

  const invoice = await createXenditInvoice(xenditSecretKey, payload);
  return { id: invoice.id, invoice_url: invoice.invoice_url, status: invoice.status };
}

const handler = createCreateInvoiceHandler({
  resolveCaller,
  findOrderByIdempotencyKey,
  loadProduct,
  createOrder,
  cancelOrder,
  attachInvoice,
  createInvoice,
  generateGuestToken,
  logger: (message) => console.error(message),
});

Deno.serve(async (request) => {
  if (!supabaseUrl || !serviceRoleKey) {
    return errorResponse(
      500,
      "SUPABASE_NOT_CONFIGURED",
      "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are missing on the server.",
    );
  }
  if (!xenditSecretKey) {
    return errorResponse(
      500,
      "XENDIT_NOT_CONFIGURED",
      "The XENDIT_SECRET_KEY edge function secret is missing on the server.",
    );
  }
  return handler(request);
});
