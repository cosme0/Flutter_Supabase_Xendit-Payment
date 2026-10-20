/**
 * Verifies that the migration also works on a project that still contains
 * the tables of the earlier (reference) implementation:
 *
 *   products(id serial, name, price, image_url)
 *   orders(id serial, external_id, product_name, amount, status, created_at)
 *
 *   node supabase/tests/pglite_legacy_upgrade_test.mjs
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
  create or replace function auth.uid() returns uuid
    language sql stable
    as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table if not exists auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    created_at timestamptz not null default now()
  );
`);

console.log("Creating the LEGACY tables (as the reference implementation did) ...");
await db.exec(`
  create table public.products (
    id serial primary key,
    name text not null,
    price numeric(12,2) not null,
    image_url text
  );
  insert into public.products (name, price, image_url)
  values ('Legacy keyboard', 999, 'https://example.com/legacy.jpg');

  create table public.orders (
    id serial primary key,
    external_id text,
    product_name text not null,
    amount numeric(12,2) not null,
    status text not null default 'PENDING',
    created_at timestamptz not null default now()
  );
  insert into public.orders (external_id, product_name, amount, status)
  values ('legacy-1', 'Legacy keyboard', 999, 'PENDING');
`);

console.log("Applying the migration ...\n");
const schema = readFileSync(join(migrationsDir, "001_initial_schema.sql"), "utf8");
await db.exec(schema);
const seed = readFileSync(join(migrationsDir, "002_seed_demo_products.sql"), "utf8");
await db.exec(seed);

console.log("== the legacy tables were replaced ==");
const productIdType = await db.query(
  `select data_type from information_schema.columns
    where table_schema='public' and table_name='products' and column_name='id'`,
);
checkEqual(productIdType.rows[0].data_type, "uuid", "products.id is a uuid now");

const orderIdType = await db.query(
  `select data_type from information_schema.columns
    where table_schema='public' and table_name='orders' and column_name='id'`,
);
checkEqual(orderIdType.rows[0].data_type, "uuid", "orders.id is a uuid now");

const productColumns = await db.query(
  `select column_name from information_schema.columns
    where table_schema='public' and table_name='products'`,
);
const productColumnNames = productColumns.rows.map((row) => row.column_name);
for (const column of ["description", "stock_quantity", "is_active", "updated_at"]) {
  check(productColumnNames.includes(column), `products.${column} exists`);
}

const orderColumns = await db.query(
  `select column_name from information_schema.columns
    where table_schema='public' and table_name='orders'`,
);
const orderColumnNames = orderColumns.rows.map((row) => row.column_name);
for (const column of [
  "payment_status",
  "currency",
  "total_amount",
  "user_id",
  "guest_token_hash",
  "xendit_invoice_id",
  "xendit_invoice_url",
  "idempotency_key",
  "paid_at",
  "updated_at",
]) {
  check(orderColumnNames.includes(column), `orders.${column} exists`);
}

console.log("\n== the demo catalogue is available again ==");
const products = await db.query(`select name, price from public.products order by name`);
checkEqual(products.rows.length, 3, "three demo products");
const keyboard = products.rows.find((row) => row.name === "Mechanical Gaming Keyboard");
check(keyboard !== undefined, "the Mechanical Gaming Keyboard exists");
checkEqual(keyboard.price, "1500.00", "the keyboard costs 1500.00");

console.log("\n== the new order flow works on the upgraded database ==");
const userId = "11111111-1111-4111-8111-111111111111";
await db.exec(
  `insert into auth.users (id, email) values ('${userId}', 'demo@student.shop')`,
);
const productId = (await db.query(
  `select id from public.products where name = 'Mechanical Gaming Keyboard'`,
)).rows[0].id;

const order = await db.query(
  `select * from public.create_order($1::uuid, 1, $2::uuid, null, 'legacy-key', 'legacy-ext-1')`,
  [productId, userId],
);
checkEqual(order.rows[0].status, "PENDING", "a new order is PENDING");
checkEqual(order.rows[0].total_amount, "1500.00", "the server calculated the total");

const items = await db.query(
  `select product_name, subtotal from public.order_items where order_id = $1::uuid`,
  [order.rows[0].id],
);
checkEqual(items.rows.length, 1, "the order has one item");

await db.query(
  `update public.orders set xendit_invoice_id = 'inv-legacy' where id = $1::uuid`,
  [order.rows[0].id],
);
const paid = await db.query(
  `select * from public.apply_xendit_invoice_event(
      p_invoice_id => 'inv-legacy',
      p_external_id => 'legacy-ext-1',
      p_status => 'PAID',
      p_amount_cents => 150000,
      p_currency => 'PHP',
      p_event_key => 'evt-legacy',
      p_paid_at => now(),
      p_payment_method => 'GCASH',
      p_payload => '{}'::jsonb)`,
);
checkEqual(paid.rows[0].result, "paid", "the webhook pays the order");

console.log("\n== RLS is active on the upgraded database ==");
const rls = await db.query(
  `select tablename, rowsecurity from pg_tables where schemaname = 'public'`,
);
for (const row of rls.rows) {
  check(row.rowsecurity === true, `RLS enabled on ${row.tablename}`);
}
const writePolicies = await db.query(
  `select count(*)::int as count from pg_policies
    where schemaname = 'public' and cmd in ('INSERT','UPDATE','DELETE')`,
);
checkEqual(writePolicies.rows[0].count, 0, "no client may write to the shop tables");

console.log(`\n${checks - failures}/${checks} checks passed`);
if (failures > 0) {
  console.error(`${failures} checks FAILED`);
  process.exitCode = 1;
} else {
  console.log("The legacy upgrade works.");
}
