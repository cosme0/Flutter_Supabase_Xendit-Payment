/**
 * `xendit-webhook` edge function (Supabase project: BMC-ecom1).
 *
 * Xendit calls this endpoint when an invoice changes state ("Invoices paid",
 * "Invoice expired"). Xendit does not send a Supabase JWT, therefore the
 * platform level JWT verification is disabled for this function and the
 * request is authenticated with the `x-callback-token` header instead. The
 * token is compared against the `XENDIT_WEBHOOK_TOKEN` secret that is also
 * configured in the Xendit dashboard.
 *
 * The order is only moved to PAID by
 * `public.apply_xendit_invoice_event(...)`, which validates the invoice id,
 * the amount and the currency inside a single database transaction and is
 * idempotent for repeated deliveries.
 */
import { firstRow, createAdminClient, readServiceRoleKey, readSupabaseUrl } from "../_shared/supabase_client.ts";
import { createWebhookHandler, type WebhookApplyResult } from "../_shared/webhook_handler.ts";
import type { NormalizedInvoiceEvent } from "../_shared/validation.ts";

const supabaseUrl = readSupabaseUrl();
const serviceRoleKey = readServiceRoleKey();
const webhookToken = Deno.env.get("XENDIT_WEBHOOK_TOKEN") ?? "";

const supabase = createAdminClient(supabaseUrl, serviceRoleKey);

interface ApplyResultRow {
  result: string;
  order_id: string | null;
  order_status: string | null;
}

/** Applies a normalised Xendit event to the database. */
async function applyEvent(event: NormalizedInvoiceEvent): Promise<WebhookApplyResult> {
  const { data, error } = await supabase.rpc("apply_xendit_invoice_event", {
    p_invoice_id: event.invoiceId,
    p_external_id: event.externalId,
    p_status: event.status,
    p_amount_cents: event.amount,
    p_currency: event.currency,
    p_paid_at: event.paidAt,
    p_payment_method: event.paymentMethod,
    p_event_key: event.eventKey,
    p_payload: { invoice_id: event.invoiceId, status: event.status },
  });

  if (error) {
    console.error("apply_xendit_invoice_event failed:", error.message);
    throw new Error(error.message);
  }

  const row = firstRow<ApplyResultRow>(data);
  if (!row) {
    return { result: "no_result" };
  }

  return {
    result: row.result,
    orderId: row.order_id,
    orderStatus: row.order_status,
  };
}

const handler = createWebhookHandler({
  expectedToken: webhookToken,
  applyEvent,
  logger: (message) => console.error(message),
});

Deno.serve(handler);
