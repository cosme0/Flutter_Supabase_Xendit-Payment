import {
  assert,
  assertEquals,
  assertFalse,
  assertThrows,
  expectError,
  expectOk,
} from "./test_helpers.ts";
import {
  buildEventKey,
  classifyInvoiceStatus,
  fromMinorUnits,
  isApplicationKey,
  isGuestToken,
  isUuid,
  isValidCallbackToken,
  normalizeInvoiceEvent,
  parseCheckoutRequest,
  toMinorUnits,
} from "./validation.ts";

const PRODUCT_ID = "3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90";

Deno.test("isUuid accepts a uuid and rejects everything else", () => {
  assert(isUuid(PRODUCT_ID));
  assert(isUuid(PRODUCT_ID.toUpperCase()));
  assertFalse(isUuid("not-a-uuid"));
  assertFalse(isUuid(42));
  assertFalse(isUuid(null));
  assertFalse(isUuid(""));
});

Deno.test("parseCheckoutRequest accepts a valid request", () => {
  const value = expectOk(parseCheckoutRequest({
    product_id: PRODUCT_ID,
    quantity: 2,
  }));
  assertEquals(value.productId, PRODUCT_ID);
  assertEquals(value.quantity, 2);
});

Deno.test("parseCheckoutRequest rejects a missing or invalid product id", () => {
  assertEquals(expectError(parseCheckoutRequest({ quantity: 1 })).code, "INVALID_PRODUCT_ID");
  assertEquals(
    expectError(parseCheckoutRequest({ product_id: "keyboard", quantity: 1 })).code,
    "INVALID_PRODUCT_ID",
  );
});

Deno.test("parseCheckoutRequest rejects invalid quantities", () => {
  for (const quantity of [0, -1, 1.5, 99, "abc", null]) {
    const result = parseCheckoutRequest({ product_id: PRODUCT_ID, quantity });
    assertFalse(result.ok, `quantity ${quantity} should be rejected`);
    assertEquals(expectError(result).code, "INVALID_QUANTITY");
  }
});

Deno.test("parseCheckoutRequest defaults the quantity to one", () => {
  const value = expectOk(parseCheckoutRequest({ product_id: PRODUCT_ID }));
  assertEquals(value.quantity, 1);
});

Deno.test("parseCheckoutRequest rejects a body that is not an object", () => {
  assertEquals(expectError(parseCheckoutRequest("nope")).code, "INVALID_BODY");
});

Deno.test("parseCheckoutRequest ignores a client supplied price", () => {
  const value = expectOk(parseCheckoutRequest({
    product_id: PRODUCT_ID,
    quantity: 1,
    amount: 1,
    price: 1,
    total_amount: 1,
  })) as unknown as Record<string, unknown>;
  assertEquals(value["price"], undefined);
  assertEquals(value["amount"], undefined);
  assertEquals(value["total_amount"], undefined);
});

Deno.test("guest tokens need at least 32 characters", () => {
  assert(isGuestToken("a".repeat(64)));
  assertFalse(isGuestToken("a".repeat(31)));
  assertFalse(isGuestToken(123));
});

Deno.test("peso amounts are converted into Xendit minor units", () => {
  assertEquals(toMinorUnits(1500), 150000);
  assertEquals(toMinorUnits(1500.5), 150050);
  assertEquals(fromMinorUnits(150000), 1500);
  assertEquals(fromMinorUnits(toMinorUnits(849.99)), 849.99);
});

Deno.test("the webhook token is compared in constant time", () => {
  assert(isValidCallbackToken("super-secret", "super-secret"));
  assertFalse(isValidCallbackToken("super-secre", "super-secret"));
  assertFalse(isValidCallbackToken("super-secretx", "super-secret"));
  assertFalse(isValidCallbackToken(null, "super-secret"));
  assertFalse(isValidCallbackToken("super-secret", null));
  assertFalse(isValidCallbackToken("super-secret", ""));
  assertFalse(isValidCallbackToken("Super-Secret", "super-secret"));
});

Deno.test("invoice statuses are classified", () => {
  assertEquals(classifyInvoiceStatus("PAID"), "paid");
  assertEquals(classifyInvoiceStatus("SETTLED"), "paid");
  assertEquals(classifyInvoiceStatus("paid"), "paid");
  assertEquals(classifyInvoiceStatus("EXPIRED"), "expired");
  assertEquals(classifyInvoiceStatus("PENDING"), "pending");
  assertEquals(classifyInvoiceStatus("SOMETHING"), "unknown");
  assertEquals(classifyInvoiceStatus(undefined), "unknown");
  assertEquals(classifyInvoiceStatus(42), "unknown");
});

Deno.test("the event key is stable for repeated deliveries", () => {
  const first = buildEventKey("inv-1", "PAID", "2026-01-01T00:00:00Z");
  const second = buildEventKey("inv-1", "PAID", "2026-01-01T00:00:00Z");
  assertEquals(first, second);
  assert(first !== buildEventKey("inv-1", "EXPIRED", "2026-01-01T00:00:00Z"));
});

Deno.test("a webhook payload is normalised", () => {
  const value = expectOk(normalizeInvoiceEvent({
    id: "inv-123",
    external_id: "order-123",
    status: "PAID",
    amount: 150000,
    currency: "PHP",
    paid_at: "2026-01-01T00:00:00Z",
    payment_method: "GCASH",
  }));
  assertEquals(value.invoiceId, "inv-123");
  assertEquals(value.externalId, "order-123");
  assertEquals(value.amount, 150000);
  assertEquals(value.currency, "PHP");
  assertEquals(value.paymentMethod, "GCASH");
});

Deno.test("a webhook payload without an invoice id is rejected", () => {
  assertEquals(expectError(normalizeInvoiceEvent({ status: "PAID" })).code, "INVALID_PAYLOAD");
});

Deno.test("the project key is recognised as an application key", () => {
  const keys = ["sb_publishable_abc", "eyJhbGciOiJIUzI1NiJ9.legacy"];
  assert(isApplicationKey("sb_publishable_abc", keys));
  assert(isApplicationKey("eyJhbGciOiJIUzI1NiJ9.legacy", keys));
  assertFalse(isApplicationKey("a-user-jwt", keys));
  assertFalse(isApplicationKey("", keys));
  assertFalse(isApplicationKey("sb_publishable_abc", []));
  assertFalse(isApplicationKey("sb_publishable_abc", [""]));
});

Deno.test("assertThrows is available (sanity check for the test setup)", () => {
  assertThrows(() => {
    throw new Error("boom");
  });
});
