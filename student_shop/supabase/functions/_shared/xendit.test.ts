import { assert, assertEquals, assertRejects } from "./test_helpers.ts";
import {
  basicAuthHeader,
  buildInvoiceRequest,
  createXenditInvoice,
  XenditApiError,
  XENDIT_INVOICE_ENDPOINT,
} from "./xendit.ts";

Deno.test("the invoice request matches the Xendit v2 invoice API", () => {
  const request = buildInvoiceRequest({
    externalId: "order-1",
    productName: "Mechanical Gaming Keyboard",
    quantity: 2,
    amountMinorUnits: 300000,
  });

  assertEquals(request.external_id, "order-1");
  assertEquals(request.amount, 300000);
  assertEquals(request.currency, "PHP");
  assertEquals(request.items.length, 1);
  assertEquals(request.items[0].name, "Mechanical Gaming Keyboard");
  assertEquals(request.items[0].quantity, 2);
  assertEquals(request.items[0].price, 300000);
  // without an explicit list Xendit shows the channels of the account
  assertEquals(request.payment_methods, undefined);
});

Deno.test("the requested payment channels are sent when they are configured", () => {
  const request = buildInvoiceRequest({
    externalId: "order-1",
    productName: "Mechanical Gaming Keyboard",
    quantity: 1,
    amountMinorUnits: 150000,
    paymentMethods: ["GCASH", "MAYA"],
  });

  assertEquals(request.payment_methods, ["GCASH", "MAYA"]);
});

Deno.test("the basic auth header uses the secret key and an empty password", () => {
  const header = basicAuthHeader("xnd_development_secret");
  assertEquals(header, `Basic ${btoa("xnd_development_secret:")}`);
});

Deno.test("a successful invoice creation returns the checkout url", async () => {
  const calls: Array<[string, RequestInit | undefined]> = [];
  const fakeFetch = (input: string | URL | Request, init?: RequestInit) => {
    calls.push([String(input), init]);
    return Promise.resolve(
      new Response(
        JSON.stringify({
          id: "inv-1",
          external_id: "order-1",
          status: "PENDING",
          amount: 150000,
          currency: "PHP",
          invoice_url: "https://checkout.xendit.co/web/inv-1",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  };

  const invoice = await createXenditInvoice(
    "xnd_development_secret",
    buildInvoiceRequest({
      externalId: "order-1",
      productName: "Mechanical Gaming Keyboard",
      quantity: 1,
      amountMinorUnits: 150000,
    }),
    fakeFetch as typeof fetch,
  );

  assertEquals(invoice.id, "inv-1");
  assertEquals(invoice.invoice_url, "https://checkout.xendit.co/web/inv-1");
  assertEquals(calls[0][0], XENDIT_INVOICE_ENDPOINT);
  const headers = calls[0][1]?.headers as Record<string, string>;
  assertEquals(headers["Authorization"], basicAuthHeader("xnd_development_secret"));
});

Deno.test("an xendit error is turned into an XenditApiError", async () => {
  const fakeFetch = () =>
    Promise.resolve(
      new Response(JSON.stringify({ error_code: "DUPLICATE_PAYMENT" }), { status: 400 }),
    );

  await assertRejects(
    () =>
      createXenditInvoice(
        "secret",
        buildInvoiceRequest({
          externalId: "order-1",
          productName: "Keyboard",
          quantity: 1,
          amountMinorUnits: 150000,
        }),
        fakeFetch as typeof fetch,
      ),
    (error: unknown) => {
      assert(error instanceof XenditApiError);
      assertEquals((error as XenditApiError).status, 400);
      return true;
    },
  );
});

Deno.test("a response without an invoice url is rejected", async () => {
  const fakeFetch = () =>
    Promise.resolve(
      new Response(JSON.stringify({ id: "inv-1" }), { status: 200 }),
    );

  await assertRejects(
    () =>
      createXenditInvoice(
        "secret",
        buildInvoiceRequest({
          externalId: "order-1",
          productName: "Keyboard",
          quantity: 1,
          amountMinorUnits: 150000,
        }),
        fakeFetch as typeof fetch,
      ),
    (error: unknown) => {
      assert(error instanceof XenditApiError);
      return true;
    },
  );
});
