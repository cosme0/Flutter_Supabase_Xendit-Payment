# Supabase backend - `student_shop`

Everything in this folder belongs to the Supabase project **kfvxqsxycpmawgbwugyr**
(the backend of the *Student Shop* demonstration).

```
supabase/
  config.toml                         project + edge function configuration
  migrations/
    001_initial_schema.sql            tables (products, orders) + RLS policies
    002_seed_demo_products.sql        demo catalogue (idempotent)
  functions/
    create-invoice/index.ts           creates the Xendit invoice + the PENDING order
    xendit-webhook/index.ts           receives the Xendit notification, sets PAID
  tests/
    01_rls_verification.sql           proves that the client cannot fake a payment
```

---

## 1. Apply the database schema

1. Open the [Supabase Dashboard](https://supabase.com/dashboard) and select the
   project **kfvxqsxycpmawgbwugyr**.
2. Go to **SQL Editor -> New query**.
3. Copy the content of `migrations/001_initial_schema.sql` and press **Run**.
4. Repeat with `migrations/002_seed_demo_products.sql`.

Both scripts are idempotent - running them again does not break anything and
refreshes the demo catalogue.

### What is created?

| Object | Purpose |
| --- | --- |
| `products` | catalogue: name, price (PHP), image url |
| `orders` | one row per checkout: external id, status, product, amount |

### Row Level Security

| Table | Policy |
| --- | --- |
| `products` | everybody may **read** the catalogue, nobody may write |
| `orders` | everybody may **read** the order history, **no** insert/update/delete policy |

Because there is no `insert`/`update` policy for `orders`, the Flutter client
can neither create an order nor mark an order as `PAID`. Only the edge
functions - which run with the service role key - can write to that table. A
customer can therefore never fake a payment.

You can verify this yourself with `tests/01_rls_verification.sql`.

---

## 2. Configure the edge function secrets

The secrets must **not** be committed to git. Store them as Supabase edge
function secrets (Dashboard -> **Edge Functions -> Secrets** or with the CLI).

| Secret | Value | Where to get it |
| --- | --- | --- |
| `XENDIT_SECRET_KEY` | `xnd_development_...` (test mode!) | Xendit Dashboard -> API Keys |
| `XENDIT_WEBHOOK_TOKEN` | any random string | you choose it, e.g. `openssl rand -hex 24` |
| `XENDIT_PAYMENT_METHODS` | optional, e.g. `GCASH,MAYA` | leave empty to show all channels of the account |

With the CLI:

```powershell
cd student_shop
copy supabase\.env.local.example supabase\.env.local   # fill in the values
supabase login
supabase secrets set --env-file supabase\.env.local --project-ref kfvxqsxycpmawgbwugyr
```

---

## 3. Deploy the edge functions

```powershell
cd student_shop
supabase link --project-ref kfvxqsxycpmawgbwugyr
supabase functions deploy create-invoice --project-ref kfvxqsxycpmawgbwugyr
supabase functions deploy xendit-webhook --project-ref kfvxqsxycpmawgbwugyr
```

or simply:

```powershell
powershell -ExecutionPolicy Bypass -File deploy.ps1 -ProjectRef kfvxqsxycpmawgbwugyr
```

> If PowerShell refuses to run the `supabase` shim, use `supabase.cmd` instead
> of `supabase`.

---

## 4. Configure the Xendit webhook

Dashboard -> **Developers** -> **Webhooks** -> add

```
https://kfvxqsxycpmawgbwugyr.supabase.co/functions/v1/xendit-webhook
```

* event: **Invoices paid**
* token: the same value as the `XENDIT_WEBHOOK_TOKEN` secret

Xendit then calls the edge function whenever an invoice is paid. The function
verifies the token and flips the order to `PAID` - that is the moment the app
shows *"Payment Verified! Mechanical Gaming Keyboard is PAID."*

---

## 5. Endpoints

```
POST .../functions/v1/create-invoice    -> 200 {"invoice_url":"...","external_id":"..."}
POST .../functions/v1/xendit-webhook    -> 401 {"error":"Unauthorized webhook caller"}  (no / wrong token)
GET  .../rest/v1/products              -> 200 [{"id":1,"name":"Mechanical Gaming Keyboard","price":1500.00,...}]
GET  .../rest/v1/orders                 -> 200 [{"id":1,"status":"PAID","amount":1500.00,...}]
```
