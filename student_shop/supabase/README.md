# Supabase backend - `student_shop`

Everything in this folder belongs to the Supabase project **BMC-ecom1**
(organization **BMC**, project ref `iiznhatxciycwghihnaq`).

```
supabase/
  config.toml                         # project + edge function configuration
  migrations/
    001_initial_schema.sql            # tables, RLS policies, RPC functions
    002_seed_demo_products.sql        # demo catalogue (idempotent)
  functions/
    _shared/                          # shared, unit tested helper modules
      cors.ts
      crypto.ts
      http.ts
      supabase_client.ts
      validation.ts
      xendit.ts
      create_invoice_handler.ts
      webhook_handler.ts
      test_helpers.ts
      *.test.ts                       # deno tests (43 assertions)
    create-invoice/index.ts           # creates the Xendit invoice
    xendit-webhook/index.ts           # receives the Xendit notifications
```

---

## 1. Apply the database schema

1. Open the [Supabase Dashboard](https://supabase.com/dashboard) and select
   the project **BMC-ecom1**.
2. Go to **SQL Editor -> New query**.
3. Copy the content of `migrations/001_initial_schema.sql` and press **Run**.
4. Repeat with `migrations/002_seed_demo_products.sql`.

Both scripts are idempotent - running them again does not break anything and
refreshes the demo catalogue.

What is created:

| Object | Purpose |
| --- | --- |
| `products` | catalogue: name, description, price (PHP), image url, stock, active flag |
| `orders` | pending/paid orders, Xendit invoice id, amount, currency, owner (user **or** guest) |
| `order_items` | one row per ordered product with a snapshot of name and price |
| `guest_sessions` | hashed guest tokens for the guest checkout |
| `payment_webhook_events` | every webhook delivery (unique `event_key` = idempotency) |
| `public.create_order(...)` | transactional order creation + stock reservation (service role only) |
| `public.cancel_order(...)` | releases the reserved stock when the invoice cannot be created |
| `public.apply_xendit_invoice_event(...)` | the **only** place where an order may become `PAID` |
| `public.get_my_orders(text)` | reads the orders of the current customer (used by the app) |

### Row Level Security

| Table | Policy |
| --- | --- |
| `products` | everybody may read the **active** products, nobody may write |
| `orders` | `select` only for `auth.uid() = user_id` - **no insert/update/delete policy** |
| `order_items` | `select` only for the items of your own orders |
| `guest_sessions`, `payment_webhook_events` | no client access at all |

Because there is no `insert`/`update` policy for `orders`, the Flutter client
can neither create an order nor mark an order as `PAID`. Only the edge
functions (service role) can write to those tables.

---

## 2. Configure the edge function secrets

The secrets must **not** be committed to git. Store them as Supabase edge
function secrets (Dashboard -> **Edge Functions -> Secrets** or with the CLI).

| Secret | Value | Where to get it |
| --- | --- | --- |
| `XENDIT_SECRET_KEY` | `xnd_development_...` (test mode!) | Xendit Dashboard -> API Keys |
| `XENDIT_WEBHOOK_TOKEN` | any random string | you choose it, e.g. `openssl rand -hex 24` |
| `XENDIT_PAYMENT_METHODS` | optional, e.g. `GCASH,MAYA` | leave empty to show all channels of the account |

With the Supabase CLI (the secrets are read from `supabase/.env.local`, which
is git ignored):

```bash
supabase login
supabase link --project-ref iiznhatxciycwghihnaq

supabase secrets set --env-file supabase/.env.local
```

or with the helper script in the project root: `.\deploy.ps1`.

`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (or `SUPABASE_SECRET_KEY`) and
`SUPABASE_ANON_KEY` are provided automatically by the platform.

> The `service_role` key is only used **inside** the edge functions. It is
> never part of the Flutter application.

---

## 3. Deploy the edge functions

```bash
supabase functions deploy create-invoice
supabase functions deploy xendit-webhook
```

The `verify_jwt` behaviour is configured in `config.toml`:

* `create-invoice` -> `verify_jwt = false`
  The function has to support guest checkouts, therefore the platform check is
  disabled and the function **verifies the JWT itself** (see
  `resolveCaller` in `functions/create-invoice/index.ts`). An invalid or
  expired token is rejected with `401` - it is never downgraded to a guest
  order. If you only want signed in customers, set `verify_jwt = true` again
  and enable anonymous sign-ins in the dashboard.
* `xendit-webhook` -> `verify_jwt = false` (**must stay false**)
  Xendit calls the endpoint server to server and does not send a Supabase
  JWT. Because the platform check is disabled, the function validates the
  `x-callback-token` header against the `XENDIT_WEBHOOK_TOKEN` secret in
  constant time. Without that validation anybody could mark arbitrary orders
  as `PAID`.

Local development (needs Docker):

```bash
supabase start
supabase functions serve create-invoice --env-file supabase/.env.local
supabase functions serve xendit-webhook --env-file supabase/.env.local
```

---

## 4. Point the Xendit webhook to Supabase

1. Xendit Dashboard -> **Developers -> Webhooks / Callbacks**.
2. Add the callback url of the deployed function:

   ```
   https://iiznhatxciycwghihnaq.supabase.co/functions/v1/xendit-webhook
   ```

3. Select the event **Invoices paid** (and optionally **Invoice expired**).
4. Use the **same token** in the webhook settings as in the
   `XENDIT_WEBHOOK_TOKEN` secret - Xendit sends it in the `x-callback-token`
   header of every delivery.

Xendit retries a delivery up to six times when the endpoint does not answer
with a 2xx status code, so the handler always answers `200` for events it
cannot process (and records the reason).

---

## 5. How the payment is verified

```
Flutter app                Supabase                    Xendit
     |                        |                          |
     | create-invoice         |                          |
     |----------------------->|                          |
     |                        | 1. validate request     |
     |                        | 2. read price + stock   |
     |                        | 3. create pending order |
     |                        | 4. POST /v2/invoices    |
     |                        |------------------------->|
     |                        |<-------------------------|
     |                        | 5. store invoice id     |
     |<-----------------------|                          |
     | open invoice_url       |                          |
     | customer pays ---------|------------------------->|
     |                        |<-- webhook (PAID) -------|
     |                        | 6. validate token       |
     |                        | 7. apply event (tx)     |
     |                        | 8. order.status = PAID  |
     | "Check status"         |                          |
     |----------------------->| SELECT orders (RLS)     |
     |<-----------------------| status = PAID           |
```

The app **never** decides that a payment succeeded. It only shows the status
that the database returns, and the database is only updated by the webhook
handler after it validated the invoice id, the amount and the currency.

---

## 6. Manual security checks

Run the statements below in the SQL editor (or in `supabase/tests/`) to verify
the setup.

```sql
-- a) RLS is enabled everywhere
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

-- b) there is no policy that would allow a client to write an order
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and cmd in ('INSERT', 'UPDATE', 'DELETE');

-- c) the demo product costs 1500.00 PHP
select name, price, currency, stock_quantity
from public.products
where name = 'Mechanical Gaming Keyboard';
```

To prove that a client cannot mark an order as paid, run the following as the
`anon` role (Supabase -> SQL editor -> "Run as role: anon"):

```sql
update public.orders set status = 'PAID', payment_status = 'PAID';
-- ERROR:  new row violates row-level security policy for table "orders"
```

To prove that one customer cannot see the orders of another one, sign in as a
second user and run:

```sql
select count(*) from public.orders;   -- only the orders of the current user
```

---

## 7. Tests of the backend logic

The pure business logic of the edge functions lives in `functions/_shared` and
is covered by Deno tests (no database and no Xendit account needed):

```bash
deno test --allow-env supabase/functions/_shared
```

```
ok | 43 passed | 0 failed
```

They cover: invalid input, unknown product, unavailable product, out of stock,
Xendit failures, idempotent retries, guest token issuing, webhook token
rejection, malformed payloads, paid / expired / failed / duplicate
notifications and unknown statuses.

The database migration is verified against a real PostgreSQL that runs inside
the process:

```bash
npm install @electric-sql/pglite
node supabase/tests/pglite_migration_test.mjs
```

```
51/51 checks passed
```

The script applies both migrations and checks the tables, the RLS policies,
the order creation with the stock reservation, the idempotency, the webhook
handling (paid / expired / duplicate / mismatch / unknown) and the guest
checkout.

If the project still contains the tables of the earlier reference
implementation (`products.id integer`, `orders.amount`), the migration
upgrades them automatically. That path is verified with:

```bash
node supabase/tests/pglite_legacy_upgrade_test.mjs
```

```
29/29 checks passed
```

The files in `tests/` are meant to be executed in the Supabase SQL editor of
the project:

* `01_rls_verification.sql` - shows that RLS is enabled and that no policy
  allows a client to write
* `02_negative_rls_tests.sql` - statements that **must fail** (run them with
  the role selector set to `anon`)
