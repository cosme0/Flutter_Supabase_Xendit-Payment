/**
 * Minimal Xendit Invoice API client (Xendit "Payment Link" / legacy invoice
 * endpoint `POST /v2/invoices`).
 *
 * Reference: https://developers.xendit.co/api-reference/#create-invoice
 *   * endpoint : https://api.xendit.co/v2/invoices
 *   * auth     : Basic auth, the secret key is the user name and the
 *                password is left empty -> base64("<secretKey>:")
 *   * amount   : the money is sent in the minor unit of the currency
 *                (PHP 1,500.00 -> 150000 centavos)
 *   * currency : "PHP" for the Philippine Peso
 *
 * The secret key is read from the edge function secret XENDIT_SECRET_KEY and
 * is never sent to, or embedded in, the Flutter application.
 */

export const XENDIT_INVOICE_ENDPOINT = "https://api.xendit.co/v2/invoices";

/**
 * Payment channels that can be requested for the checkout page.
 *
 * If the list is empty the field is omitted from the request and Xendit shows
 * every channel that is activated for the account (for the demo account of
 * the BMC project that is GCash). The list can be configured with the
 * `XENDIT_PAYMENT_METHODS` edge function secret, e.g.
 * `XENDIT_PAYMENT_METHODS=GCASH,MAYA`.
 */
export const DEFAULT_PAYMENT_METHODS: string[] = [];

export interface XenditInvoiceItem {
  name: string;
  quantity: number;
  price: number;
  category?: string;
  url?: string;
}

export interface XenditInvoiceRequest {
  external_id: string;
  amount: number;
  currency: string;
  description: string;
  invoice_duration: number;
  should_send_email: boolean;
  items: XenditInvoiceItem[];
  /** Omitted when the account should decide which channels are shown. */
  payment_methods?: string[];
  payer_email?: string;
  customer?: {
    given_names?: string;
    surname?: string;
    email?: string;
    mobile_number?: string;
  };
  success_redirect_url?: string;
  failure_redirect_url?: string;
  metadata?: Record<string, string>;
}

export interface XenditInvoiceResponse {
  id: string;
  external_id: string;
  status: string;
  amount: number;
  currency?: string;
  invoice_url: string;
  expiry_date?: string;
  created?: string;
  updated?: string;
  payer_email?: string;
  description?: string;
  [key: string]: unknown;
}

/** Error thrown when the Xendit API answers with a non 2xx status. */
export class XenditApiError extends Error {
  readonly status: number;
  readonly body: string;

  constructor(message: string, status: number, body: string) {
    super(message);
    this.name = "XenditApiError";
    this.status = status;
    this.body = body;
  }
}

/** Builds the `Authorization` header value for the Xendit API. */
export function basicAuthHeader(secretKey: string): string {
  const encoded = btoa(`${secretKey}:`);
  return `Basic ${encoded}`;
}

/** Builds the invoice request body for a single product checkout. */
export function buildInvoiceRequest(params: {
  externalId: string;
  productName: string;
  quantity: number;
  amountMinorUnits: number;
  currency?: string;
  payerEmail?: string;
  invoiceDurationSeconds?: number;
  successRedirectUrl?: string;
  failureRedirectUrl?: string;
  paymentMethods?: string[];
  category?: string;
}): XenditInvoiceRequest {
  const request: XenditInvoiceRequest = {
    external_id: params.externalId,
    amount: params.amountMinorUnits,
    currency: params.currency ?? "PHP",
    description: `${params.productName} x${params.quantity}`,
    invoice_duration: params.invoiceDurationSeconds ?? 3600,
    should_send_email: false,
    items: [
      {
        name: params.productName,
        quantity: params.quantity,
        price: params.amountMinorUnits,
        category: params.category ?? "Electronic",
      },
    ],
  };

  // An empty list means: let Xendit show the channels of the account.
  const paymentMethods = params.paymentMethods ?? DEFAULT_PAYMENT_METHODS;
  if (paymentMethods.length > 0) {
    request.payment_methods = paymentMethods;
  }

  if (params.payerEmail) {
    request.payer_email = params.payerEmail;
    request.customer = {
      given_names: "Student",
      surname: "Shopper",
      email: params.payerEmail,
    };
  }
  if (params.successRedirectUrl) request.success_redirect_url = params.successRedirectUrl;
  if (params.failureRedirectUrl) request.failure_redirect_url = params.failureRedirectUrl;

  request.metadata = {
    order_external_id: params.externalId,
  };

  return request;
}

/**
 * Creates an invoice through the Xendit API.
 * The `fetcher` can be replaced in tests.
 */
export async function createXenditInvoice(
  secretKey: string,
  payload: XenditInvoiceRequest,
  fetcher: typeof fetch = fetch,
): Promise<XenditInvoiceResponse> {
  const response = await fetcher(XENDIT_INVOICE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": basicAuthHeader(secretKey),
    },
    body: JSON.stringify(payload),
  });

  const text = await response.text();

  if (!response.ok) {
    throw new XenditApiError(
      `Xendit returned HTTP ${response.status}.`,
      response.status,
      text.slice(0, 500),
    );
  }

  let parsed: XenditInvoiceResponse;
  try {
    parsed = JSON.parse(text) as XenditInvoiceResponse;
  } catch {
    throw new XenditApiError("Xendit returned a response that is not valid JSON.", 502, text.slice(0, 500));
  }

  if (!parsed.id || !parsed.invoice_url) {
    throw new XenditApiError("Xendit did not return an invoice id / invoice url.", 502, text.slice(0, 500));
  }

  return parsed;
}
