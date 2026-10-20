import { assert, assertEquals, assertFalse } from "./test_helpers.ts";
import {
  CheckoutError,
  createCreateInvoiceHandler,
  type CallerIdentity,
  type OrderRecord,
  type ProductRecord,
} from "./create_invoice_handler.ts";

const PRODUCT_ID = "3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90";
const KEYBOARD: ProductRecord = {
  id: PRODUCT_ID,
  name: "Mechanical Gaming Keyboard",
  price: 1500,
  stockQuantity: 25,
  isActive: true,
};

interface Harness {
  handler: (request: Request) => Promise<Response>;
  calls: {
    createOrder: number;
    createInvoice: number;
    cancelOrder: number;
    attachInvoice: number;
  };
  lastOrder: OrderRecord | null;
  setStock: (stock: number) => void;
  setActive: (active: boolean) => void;
  setExistingOrder: (order: OrderRecord | null) => void;
  setCaller: (caller: CallerIdentity) => void;
}

function buildHarness(): Harness {
  const calls = { createOrder: 0, createInvoice: 0, cancelOrder: 0, attachInvoice: 0 };
  let stock = KEYBOARD.stockQuantity;
  let active = KEYBOARD.isActive;
  let existingOrder: OrderRecord | null = null;
  let caller: CallerIdentity = { userId: "user-1", guestToken: null, isNewGuest: false };
  let lastOrder: OrderRecord | null = null;

  const handler = createCreateInvoiceHandler({
    resolveCaller: async () => caller,
    findOrderByIdempotencyKey: async () => existingOrder,
    loadProduct: async (productId) =>
      productId === PRODUCT_ID ? { ...KEYBOARD, stockQuantity: stock, isActive: active } : null,
    createOrder: async (args) => {
      calls.createOrder += 1;
      lastOrder = {
        id: "order-1",
        externalId: "order-1",
        totalAmount: args.product.price * args.quantity,
        currency: "PHP",
        status: "PENDING",
        xenditInvoiceId: null,
        xenditInvoiceUrl: null,
      };
      return lastOrder;
    },
    cancelOrder: async () => {
      calls.cancelOrder += 1;
    },
    attachInvoice: async () => {
      calls.attachInvoice += 1;
    },
    createInvoice: async () => {
      calls.createInvoice += 1;
      return { id: "inv-1", invoice_url: "https://checkout.xendit.co/web/inv-1" };
    },
    generateGuestToken: () => "g".repeat(64),
  });

  return {
    handler,
    calls,
    get lastOrder() {
      return lastOrder;
    },
    setStock: (value) => {
      stock = value;
    },
    setActive: (value) => {
      active = value;
    },
    setExistingOrder: (value) => {
      existingOrder = value;
    },
    setCaller: (value) => {
      caller = value;
    },
  };
}

function postRequest(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://functions.supabase.co/create-invoice", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

Deno.test("create-invoice returns the checkout url for a valid request", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    postRequest({ product_id: PRODUCT_ID, quantity: 1 }),
  );

  assertEquals(response.status, 201);
  const body = await response.json();
  assertEquals(body.order_id, "order-1");
  assertEquals(body.invoice_id, "inv-1");
  assertEquals(body.invoice_url, "https://checkout.xendit.co/web/inv-1");
  assertEquals(body.amount, 150000);
  assertEquals(body.amount_display, 1500);
  assertEquals(body.currency, "PHP");
  assertEquals(harness.calls.createInvoice, 1);
});

Deno.test("create-invoice rejects a request without a product id", async () => {
  const harness = buildHarness();
  const response = await harness.handler(postRequest({ quantity: 1 }));

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.code, "INVALID_PRODUCT_ID");
  assertEquals(harness.calls.createOrder, 0);
  assertEquals(harness.calls.createInvoice, 0);
});

Deno.test("create-invoice rejects an invalid quantity", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    postRequest({ product_id: PRODUCT_ID, quantity: 0 }),
  );

  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "INVALID_QUANTITY");
  assertEquals(harness.calls.createOrder, 0);
});

Deno.test("create-invoice rejects an unknown product", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    postRequest({ product_id: "00000000-0000-4000-8000-000000000000", quantity: 1 }),
  );

  assertEquals(response.status, 404);
  assertEquals((await response.json()).code, "PRODUCT_NOT_FOUND");
});

Deno.test("create-invoice refuses to sell an unavailable product", async () => {
  const harness = buildHarness();
  harness.setActive(false);

  const response = await harness.handler(
    postRequest({ product_id: PRODUCT_ID, quantity: 1 }),
  );

  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "PRODUCT_UNAVAILABLE");
  assertEquals(harness.calls.createOrder, 0);
});

Deno.test("create-invoice refuses to sell more than the available stock", async () => {
  const harness = buildHarness();
  harness.setStock(1);

  const response = await harness.handler(
    postRequest({ product_id: PRODUCT_ID, quantity: 5 }),
  );

  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "OUT_OF_STOCK");
  assertEquals(harness.calls.createOrder, 0);
});

Deno.test("create-invoice cancels the order when Xendit fails", async () => {
  const harness = buildHarness();
  const handler = createCreateInvoiceHandler({
    resolveCaller: async () => ({ userId: "u", guestToken: null, isNewGuest: false }),
    findOrderByIdempotencyKey: async () => null,
    loadProduct: async () => KEYBOARD,
    createOrder: async () => ({
      id: "order-1",
      externalId: "order-1",
      totalAmount: 1500,
      currency: "PHP",
      status: "PENDING",
      xenditInvoiceId: null,
      xenditInvoiceUrl: null,
    }),
    cancelOrder: async () => {
      harness.calls.cancelOrder += 1;
    },
    attachInvoice: async () => {},
    createInvoice: async () => {
      throw new Error("xendit is down");
    },
    generateGuestToken: () => "g".repeat(64),
  });

  const response = await handler(postRequest({ product_id: PRODUCT_ID, quantity: 1 }));

  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "XENDIT_ERROR");
  assertEquals(harness.calls.cancelOrder, 1);
});

Deno.test("create-invoice replays an existing order instead of charging twice", async () => {
  const harness = buildHarness();
  harness.setExistingOrder({
    id: "order-1",
    externalId: "order-1",
    totalAmount: 1500,
    currency: "PHP",
    status: "PENDING",
    xenditInvoiceId: "inv-1",
    xenditInvoiceUrl: "https://checkout.xendit.co/web/inv-1",
  });

  const response = await harness.handler(
    postRequest(
      { product_id: PRODUCT_ID, quantity: 1 },
      { "idempotency-key": "key-1" },
    ),
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.idempotent_replay, true);
  assertEquals(body.invoice_url, "https://checkout.xendit.co/web/inv-1");
  assertEquals(harness.calls.createOrder, 0);
  assertEquals(harness.calls.createInvoice, 0);
});

Deno.test("create-invoice issues a guest token for guest checkout", async () => {
  const harness = buildHarness();
  harness.setCaller({ userId: null, guestToken: null, isNewGuest: true });

  const response = await harness.handler(
    postRequest({ product_id: PRODUCT_ID, quantity: 1 }),
  );

  assertEquals(response.status, 201);
  const body = await response.json();
  assertEquals(body.guest_token, "g".repeat(64));
});

Deno.test("create-invoice rejects a request with an invalid access token", async () => {
  const harness = buildHarness();
  const handler = createCreateInvoiceHandler({
    resolveCaller: async () => {
      throw new CheckoutError(401, "INVALID_TOKEN", "The access token is invalid.");
    },
    findOrderByIdempotencyKey: async () => null,
    loadProduct: async () => KEYBOARD,
    createOrder: async () => {
      throw new Error("must not be called");
    },
    cancelOrder: async () => {},
    attachInvoice: async () => {},
    createInvoice: async () => {
      throw new Error("must not be called");
    },
    generateGuestToken: () => "g".repeat(64),
  });

  const response = await handler(postRequest({ product_id: PRODUCT_ID, quantity: 1 }));

  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "INVALID_TOKEN");
});

Deno.test("create-invoice answers CORS preflight requests", async () => {
  const harness = buildHarness();
  const response = await harness.handler(
    new Request("https://functions.supabase.co/create-invoice", { method: "OPTIONS" }),
  );

  assertEquals(response.status, 200);
  assertFalse(response.headers.get("Access-Control-Allow-Origin") === null);
});
