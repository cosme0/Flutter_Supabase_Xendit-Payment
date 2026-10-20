import { assert, assertEquals } from "./test_helpers.ts";
import { createWebhookHandler, type WebhookApplyResult } from "./webhook_handler.ts";
import type { NormalizedInvoiceEvent } from "./validation.ts";

const TOKEN = "xendit-webhook-secret";
const INVOICE_ID = "inv-123";
const EXTERNAL_ID = "order-123";

interface Harness {
  handler: (request: Request) => Promise<Response>;
  applied: NormalizedInvoiceEvent[];
  setResult: (result: WebhookApplyResult) => void;
  setFailure: (fail: boolean) => void;
}

function buildHarness(): Harness {
  const applied: NormalizedInvoiceEvent[] = [];
  let result: WebhookApplyResult = { result: "paid", orderId: "order-1", orderStatus: "PAID" };
  let fail = false;

  const handler = createWebhookHandler({
    expectedToken: TOKEN,
    applyEvent: async (event) => {
      if (fail) throw new Error("database is unavailable");
      applied.push(event);
      return result;
    },
    logger: () => {},
  });

  return {
    handler,
    applied,
    setResult: (value) => {
      result = value;
    },
    setFailure: (value) => {
      fail = value;
    },
  };
}

function webhookRequest(body: unknown, token: string | null = TOKEN): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token !== null) headers["x-callback-token"] = token;
  return new Request("https://functions.supabase.co/xendit-webhook", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const PAID_PAYLOAD = {
  id: INVOICE_ID,
  external_id: EXTERNAL_ID,
  status: "PAID",
  amount: 150000,
  currency: "PHP",
  paid_at: "2026-01-01T00:00:00Z",
  payment_method: "GCASH",
};

Deno.test("a webhook with a valid token is processed", async () => {
  const harness = buildHarness();
  const response = await harness.handler(webhookRequest(PAID_PAYLOAD));

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.received, true);
  assertEquals(body.result, "paid");
  assertEquals(body.order_status, "PAID");
  assertEquals(harness.applied.length, 1);
  assertEquals(harness.applied[0].invoiceId, INVOICE_ID);
  assertEquals(harness.applied[0].amount, 150000);
  assertEquals(harness.applied[0].currency, "PHP");
});

Deno.test("a webhook without the callback token is rejected", async () => {
  const harness = buildHarness();
  const response = await harness.handler(webhookRequest(PAID_PAYLOAD, null));

  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "INVALID_CALLBACK_TOKEN");
  assertEquals(harness.applied.length, 0);
});

Deno.test("a webhook with a wrong callback token is rejected", async () => {
  const harness = buildHarness();
  const response = await harness.handler(webhookRequest(PAID_PAYLOAD, "wrong-token"));

  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "INVALID_CALLBACK_TOKEN");
  assertEquals(harness.applied.length, 0);
});

Deno.test("a malformed webhook body is rejected", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    new Request("https://functions.supabase.co/xendit-webhook", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-callback-token": TOKEN },
      body: "not json",
    }),
  );

  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "INVALID_JSON");
  assertEquals(harness.applied.length, 0);
});

Deno.test("a webhook without an invoice id is rejected", async () => {
  const harness = buildHarness();
  const response = await harness.handler(webhookRequest({ status: "PAID" }));

  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "INVALID_PAYLOAD");
  assertEquals(harness.applied.length, 0);
});

Deno.test("a duplicate delivery is reported as duplicate", async () => {
  const harness = buildHarness();
  harness.setResult({ result: "duplicate", orderId: "order-1", orderStatus: "PAID" });

  const response = await harness.handler(webhookRequest(PAID_PAYLOAD));

  assertEquals(response.status, 200);
  assertEquals((await response.json()).result, "duplicate");
});

Deno.test("an expired invoice is reported as expired", async () => {
  const harness = buildHarness();
  harness.setResult({ result: "expired", orderId: "order-1", orderStatus: "EXPIRED" });

  const response = await harness.handler(
    webhookRequest({ ...PAID_PAYLOAD, status: "EXPIRED", paid_at: undefined }),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.result, "expired");
  assertEquals(body.order_status, "EXPIRED");
});

Deno.test("a failed payment never marks the order as paid", async () => {
  const harness = buildHarness();
  harness.setResult({ result: "ignored", orderId: "order-1", orderStatus: "PENDING" });

  const response = await harness.handler(
    webhookRequest({ ...PAID_PAYLOAD, status: "PENDING" }),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.result, "ignored");
  assert(body.order_status !== "PAID");
});

Deno.test("an unsupported status is ignored", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    webhookRequest({ ...PAID_PAYLOAD, status: "SOMETHING_ELSE" }),
  );

  assertEquals(response.status, 200);
  assertEquals((await response.json()).result, "ignored_status");
  assertEquals(harness.applied.length, 0);
});

Deno.test("a database error is reported with 500 so that Xendit retries", async () => {
  const harness = buildHarness();
  harness.setFailure(true);

  const response = await harness.handler(webhookRequest(PAID_PAYLOAD));

  assertEquals(response.status, 500);
  assertEquals((await response.json()).code, "WEBHOOK_PROCESSING_FAILED");
});

Deno.test("the webhook only accepts POST", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    new Request("https://functions.supabase.co/xendit-webhook", { method: "GET" }),
  );

  assertEquals(response.status, 405);
});
