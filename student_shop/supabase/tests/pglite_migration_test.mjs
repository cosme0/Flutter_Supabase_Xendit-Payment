/**
 * Executes the Supabase migrations against a real PostgreSQL (PGlite) and
 * verifies the schema, the RLS policies and the server side functions.
 *
 *   node supabase/tests/pglite_migration_test.mjs
 *
 * The script creates the `auth` schema (with the `auth.users` table that the
 * `orders` table references) before the migration is applied, because that
 * schema is provided by the Supabase platform.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, "..", "migrations");

let failures = 0;
let checks = 0;

function check(condition, message) {
  checks += 1;
  if (condition) {
    console.log(`  ok   ${message}`);
  } else {
    failures += 1;
    console.error(`  FAIL ${message}`);
  }
}

function checkEqual(actual, expected, message) {
  check(
    Object.is(actual, expected) || String(actual) === String(expected),
    `${message} (expected ${expected}, got ${actual})`,
  );
}

const db = new PGlite({ extensions: { pgcrypto } });

console.log("Preparing the platform schema ...");
await db.exec(`
  create schema if not exists extensions;
  create schema if not exists auth;

  -- the roles are provided by the Supabase platform
  do $$
  begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
      create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
      create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
      create role service_role nologin bypassrls;
    end if;
  end$$;

  -- the helper that Supabase provides for the JWT subject
  create or replace function auth.uid() returns uuid
    language sql stable
    as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

  create table if not exists auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    created_at timestamptz not null default now()
  );
  insert into auth.users (id, email)
  values ('11111111-1111-4111-8111-111111111111', 'demo@student.shop');
`);

console.log("Applying supabase/migrations/001_initial_schema.sql ...");
const schema = readFileSync(join(migrationsDir, "001_initial_schema.sql"), "utf8");
await db.exec(schema);
console.log("Applying supabase/migrations/002_seed_demo_products.sql ...");
const seed = readFileSync(join(migrationsDir, "002_seed_demo_products.sql"), "utf8");
await db.exec(seed);

console.log("\n== tables ==");
const tables = await db.query(
  `select tablename from pg_tables where schemaname = 'public' order by tablename`,
);
const tableNames = tables.rows.map((row) => row.tablename);
for (const expected of [
  "guest_sessions",
  "order_items",
  "orders",
  "payment_webhook_events",
  "products",
]) {
  check(tableNames.includes(expected), `table ${expected} exists`);
}

console.log("\n== row level security ==");
const rls = await db.query(
  `select tablename, rowsecurity from pg_tables where schemaname = 'public'`,
);
for (const row of rls.rows) {
  check(row.rowsecurity === true, `RLS enabled on ${row.tablename}`);
}

const writePolicies = await db.query(
  `select tablename, policyname, cmd from pg_policies
    where schemaname = 'public' and cmd in ('INSERT','UPDATE','DELETE')`,
);
checkEqual(writePolicies.rows.length, 0, "no client may write to the shop tables");

const orderPolicies = await db.query(
  `select cmd, qual from pg_policies
    where schemaname = 'public' and tablename = 'orders'`,
);
checkEqual(orderPolicies.rows.length, 1, "orders has exactly one policy");
checkEqual(orderPolicies.rows[0].cmd, "SELECT", "the orders policy is a SELECT");
check(
  String(orderPolicies.rows[0].qual).includes("auth.uid()"),
  "the orders policy is bound to auth.uid()",
);

console.log("\n== demo data ==");
const products = await db.query(
  `select name, price, stock_quantity from public.products order by name`,
);
checkEqual(products.rows.length, 3, "three demo products were inserted");
const keyboard = products.rows.find(
  (row) => row.name === "Mechanical Gaming Keyboard",
);
check(keyboard !== undefined, "the Mechanical Gaming Keyboard exists");
checkEqual(keyboard.price, "1500.00", "the keyboard costs 1500.00");

// The seed must be repeatable.
await db.exec(seed);
const productsAgain = await db.query(`select count(*)::int as count from public.products`);
checkEqual(productsAgain.rows[0].count, 3, "running the seed again does not duplicate rows");

console.log("\n== order creation ==");
const userId = "11111111-1111-4111-8111-111111111111";
const productId = keyboard.id ?? (await db.query(
  `select id from public.products where name = 'Mechanical Gaming Keyboard'`,
)).rows[0].id;

const order = await db.query(
  `select * from public.create_order(
      $1::uuid, 2, $2::uuid, null, 'key-1', 'order-ext-1')`,
  [productId, userId],
);
checkEqual(order.rows[0].status, "PENDING", "a new order is PENDING");
checkEqual(order.rows[0].total_amount, "3000.00", "the server calculated the total");
checkEqual(order.rows[0].currency, "PHP", "the order currency is PHP");
const orderId = order.rows[0].id;

const stockAfter = await db.query(
  `select stock_quantity from public.products where id = $1::uuid`,
  [productId],
);
checkEqual(stockAfter.rows[0].stock_quantity, 23, "the stock was reserved");

const items = await db.query(
  `select product_name, quantity, unit_price, subtotal from public.order_items where order_id = $1::uuid`,
  [orderId],
);
checkEqual(items.rows.length, 1, "the order has one item");
checkEqual(items.rows[0].quantity, 2, "the item quantity was stored");
checkEqual(items.rows[0].product_name, "Mechanical Gaming Keyboard", "the product name was snapshotted");
checkEqual(items.rows[0].subtotal, "3000.00", "the subtotal is correct");

console.log("\n== idempotency ==");
const replay = await db.query(
  `select * from public.create_order(
      $1::uuid, 2, $2::uuid, null, 'key-1', 'order-ext-1')`,
  [productId, userId],
);
checkEqual(replay.rows[0].id, orderId, "the same idempotency key returns the same order");
const orderCount = await db.query(`select count(*)::int as count from public.orders`);
checkEqual(orderCount.rows[0].count, 1, "no second order was created");

console.log("\n== stock protection ==");
let outOfStock = null;
try {
  // 50 pieces are allowed by the API, but only 23 are in stock
  await db.query(
    `select * from public.create_order($1::uuid, 50, $2::uuid, null, 'key-2', 'order-ext-2')`,
    [productId, userId],
  );
} catch (error) {
  outOfStock = error.message;
}
check(outOfStock !== null, "an order that exceeds the stock is rejected");
check(
  String(outOfStock).includes("OUT_OF_STOCK"),
  "the rejection reports OUT_OF_STOCK",
);

console.log("\n== webhook handling ==");
await db.query(
  `update public.orders set xendit_invoice_id = 'inv-1', xendit_invoice_url = 'https://checkout.xendit.co/web/inv-1' where id = $1::uuid`,
  [orderId],
);

const paid = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-1',
      p_external_id => 'order-ext-1',
      p_status => 'PAID',
      p_amount_cents => 300000,
      p_currency => 'PHP',
      p_event_key => 'evt-1',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(paid.rows[0].result, "paid", "a valid payment notification pays the order");
checkEqual(paid.rows[0].order_status, "PAID", "the order status is PAID");

const duplicate = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-1',
      p_external_id => 'order-ext-1',
      p_status => 'PAID',
      p_amount_cents => 300000,
      p_currency => 'PHP',
      p_event_key => 'evt-1',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(duplicate.rows[0].result, "duplicate", "a repeated delivery is idempotent");

const afterDuplicate = await db.query(
  `select status, payment_status from public.orders where id = $1::uuid`,
  [orderId],
);
checkEqual(afterDuplicate.rows[0].status, "PAID", "the order is still PAID");

// A second (different) event key for an already paid order must not change it.
const secondPaid = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-1',
      p_external_id => 'order-ext-1',
      p_status => 'PAID',
      p_amount_cents => 300000,
      p_currency => 'PHP',
      p_event_key => 'evt-2',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(secondPaid.rows[0].result, "already_paid", "a paid order is never downgraded");

console.log("\n== mismatch protection ==");
const secondOrder = await db.query(
  `select * from public.create_order(
      $1::uuid, 1, $2::uuid, null, 'key-3', 'order-ext-3')`,
  [productId, userId],
);
const secondOrderId = secondOrder.rows[0].id;
await db.query(
  `update public.orders set xendit_invoice_id = 'inv-2' where id = $1::uuid`,
  [secondOrderId],
);

const wrongAmount = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-2',
      p_external_id => 'order-ext-3',
      p_status => 'PAID',
      p_amount_cents => 1,
      p_currency => 'PHP',
      p_event_key => 'evt-3',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(wrongAmount.rows[0].result, "mismatch", "a wrong amount does not pay the order");
const afterMismatch = await db.query(
  `select status from public.orders where id = $1::uuid`,
  [secondOrderId],
);
checkEqual(afterMismatch.rows[0].status, "PENDING", "the order stays PENDING");

const wrongCurrency = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-2',
      p_external_id => 'order-ext-3',
      p_status => 'PAID',
      p_amount_cents => 150000,
      p_currency => 'USD',
      p_event_key => 'evt-4',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(wrongCurrency.rows[0].result, "mismatch", "a wrong currency does not pay the order");

const unknownInvoice = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'does-not-exist',
      p_external_id => 'nope',
      p_status => 'PAID',
      p_amount_cents => 150000,
      p_currency => 'PHP',
      p_event_key => 'evt-5',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(unknownInvoice.rows[0].result, "not_found", "an unknown invoice is ignored");

console.log("\n== expired invoices ==");
const expired = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-2',
      p_external_id => 'order-ext-3',
      p_status => 'EXPIRED',
      p_amount_cents => 150000,
      p_currency => 'PHP',
      p_event_key => 'evt-6',
      p_paid_at => null,
      p_payment_method => null,
      p_payload => '{}'::jsonb)`,
);
checkEqual(expired.rows[0].result, "expired", "an expired invoice expires the order");
const afterExpiry = await db.query(
  `select status, payment_status from public.orders where id = $1::uuid`,
  [secondOrderId],
);
checkEqual(afterExpiry.rows[0].status, "EXPIRED", "the order status is EXPIRED");

const stockAfterExpiry = await db.query(
  `select stock_quantity from public.products where id = $1::uuid`,
  [productId],
);
checkEqual(stockAfterExpiry.rows[0].stock_quantity, 23, "the reserved stock was returned");

console.log("\n== pending notifications ==");
const pending = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-2',
      p_external_id => 'order-ext-3',
      p_status => 'PENDING',
      p_amount_cents => 150000,
      p_currency => 'PHP',
      p_event_key => 'evt-7',
      p_paid_at => null,
      p_payment_method => null,
      p_payload => '{}'::jsonb)`,
);
checkEqual(pending.rows[0].result, "ignored", "a pending notification changes nothing");

console.log("\n== guest checkout ==");
const guestToken = "b".repeat(64);
const guestOrder = await db.query(
  `select * from public.create_order($1::uuid, 1, null, $2::text, 'key-4', 'order-ext-4')`,
  [productId, guestToken],
);
checkEqual(guestOrder.rows[0].user_id, null, "a guest order has no user id");
check(
  guestOrder.rows[0].guest_token_hash !== null &&
    guestOrder.rows[0].guest_token_hash !== guestToken,
  "the raw guest token is not stored",
);
checkEqual(
  guestOrder.rows[0].guest_token_hash.length,
  64,
  "the guest token is stored as a sha256 hash",
);

const guestOrders = await db.query(
  `select public.get_my_orders($1::text) as orders`,
  [guestToken],
);
checkEqual(guestOrders.rows[0].orders.length, 1, "the guest sees its own order");

const otherGuestOrders = await db.query(
  `select public.get_my_orders($1::text) as orders`,
  ["c".repeat(64)],
);
checkEqual(otherGuestOrders.rows[0].orders.length, 0, "another guest sees nothing");

// Simulate a signed in customer (Supabase sets request.jwt.claim.sub).
await db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [userId]);
const signedInOrders = await db.query(
  `select public.get_my_orders(null::text) as orders`,
);
check(
  signedInOrders.rows[0].orders.length >= 1,
  "get_my_orders returns the orders of the signed in customer",
);
check(
  signedInOrders.rows[0].orders[0].items.length >= 1,
  "the order of the signed in customer contains its items",
);
await db.query(`select set_config('request.jwt.claim.sub', '', false)`);

console.log("\n== cancel order ==");
const cancelled = await db.query(
  `select public.cancel_order($1::uuid, 'test') as cancelled`,
  [orderId],
);
checkEqual(cancelled.rows[0].cancelled, false, "a paid order cannot be cancelled");

console.log(`\n${checks - failures}/${checks} checks passed`);
if (failures > 0) {
  console.error(`${failures} checks FAILED`);
  process.exitCode = 1;
} else {
  console.log("All database checks passed.");
}
