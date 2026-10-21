# Student Shop - Flutter + Supabase + Xendit

BMC finals project (Act 4 - E-commerce Guidelines). A small but complete
e-commerce Android application: a student shop catalogue, a Xendit hosted
checkout and an order history whose payment status is **always** verified by
the server.

| | |
| --- | --- |
| Frontend | Flutter 3.47 / Dart 3.13 (Android APK) |
| Backend | Supabase (PostgreSQL + Edge Functions on Deno) |
| Payments | Xendit Invoice API (`POST /v2/invoices`) in **test mode** |
| Currency | Philippine Peso (PHP), demo product: **₱1,500.00** |
| Supabase project | `BMC-ecom1` (organization `BMC`), project ref `kfvxqsxycpmawgbwugyr` |

---

## 1. Features

* **Catalogue** - the store reads the active products from Supabase
  (`products` table) and shows them with image, price and a *Buy Now* button.
* **Checkout** - *Buy Now* calls the `create-invoice` edge function, which
  creates a Xendit invoice and a `PENDING` order and returns the hosted
  checkout url. The url opens inside an in-app WebView.
* **Verification** - the client never decides on its own that a payment was
  successful. After the customer taps *Done*, the app asks the **server** for
  the status of the order and only shows *"Payment Verified! ... is PAID."*
  when the database really says `PAID`.
* **Order history** - the receipt icon in the app bar opens the order history
  with a green `PAID` badge (and an orange one for pending orders).
* **Security** - the app talks to the database with the *public* publishable
  key. There is no `insert`/`update` policy on the `orders` table, so a client
  can neither create an order nor mark it as paid.

---

## 2. Project layout

```
student_shop/
├── lib/
│   ├── main.dart                        entry point + Supabase.initialize
│   ├── config/app_config.dart           project url + publishable key
│   ├── models/product_model.dart        the product of the catalogue
│   ├── screens/
│   │   ├── product_list_screen.dart     the store (Buy Now, receipt icon)
│   │   ├── xendit_webview_screen.dart   the Xendit checkout (Done button)
│   │   └── orders_screen.dart           the order history (PAID badge)
│   └── services/payment_service.dart    catalogue, invoice, status, orders
├── supabase/
│   ├── migrations/                      schema + demo catalogue
│   ├── functions/                       create-invoice, xendit-webhook
│   └── tests/01_rls_verification.sql    the client cannot fake a payment
├── test/                                Flutter unit + widget tests
├── docs/FLUTTER_CODE.md                 code walk-through
├── build-apk.ps1                        one-shot release build
└── deploy.ps1                           one-shot backend deployment
```

---

## 3. Setup

### 3.1 Supabase

1. Open the [Supabase Dashboard](https://supabase.com/dashboard) and select the
   project **BMC-ecom1** (`kfvxqsxycpmawgbwugyr`).
2. **SQL Editor** -> run `supabase/migrations/001_initial_schema.sql` and then
   `supabase/migrations/002_seed_demo_products.sql`.
3. **Edge Functions -> Secrets** -> add

   | Secret | Value |
   | --- | --- |
   | `XENDIT_SECRET_KEY` | `xnd_development_...` (Xendit **test mode** key) |
   | `XENDIT_WEBHOOK_TOKEN` | any random string, e.g. `openssl rand -hex 24` |

4. Deploy the functions:

   ```powershell
   supabase link --project-ref kfvxqsxycpmawgbwugyr
   supabase functions deploy create-invoice --project-ref kfvxqsxycpmawgbwugyr
   supabase functions deploy xendit-webhook --project-ref kfvxqsxycpmawgbwugyr
   ```

   (or `powershell -ExecutionPolicy Bypass -File deploy.ps1 -ProjectRef kfvxqsxycpmawgbwugyr`)

### 3.2 Xendit

Dashboard -> **Developers** -> **Webhooks** -> add

```
https://kfvxqsxycpmawgbwugyr.supabase.co/functions/v1/xendit-webhook
```

* event: **Invoices paid**
* token: the same value as `XENDIT_WEBHOOK_TOKEN`

### 3.3 The app

```powershell
copy .env.example .env
```

```env
SUPABASE_URL=https://kfvxqsxycpmawgbwugyr.supabase.co
SUPABASE_ANON_KEY=sb_publishable_...
```

The `.env` is git ignored. Only the **public** key is ever compiled into the
APK - the service role key and the Xendit secret stay in Supabase.

---

## 4. Build the release APK

```powershell
flutter build apk --release --dart-define-from-file=.env
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

> On machines with *Windows Smart App Control / WDAC* enabled, Flutter's
> unsigned `font-subset.exe` helper is blocked by the Application Control
> policy. Add `--no-tree-shake-icons` to the command (the icon font is then
> shipped un-subsetted, which only makes the APK ~1 MB bigger).

---

## 5. Demonstration walk-through

1. Install `app-release.apk` on an Android phone and open **Student Shop**.
2. Tap **Buy Now** on the *Mechanical Gaming Keyboard* (₱1,500.00).
3. The **Xendit WebView** opens -> select **GCash** or **Maya** -> tap the test
   simulation button.
4. Wait for Xendit's green receipt page inside the WebView - at that exact
   moment the Xendit webhook updates Supabase in the background.
5. Tap **Done** in the top right corner of the app bar.
6. A green snackbar appears: **"Payment Verified! Mechanical Gaming Keyboard is PAID."**
7. Tap the **receipt icon** in the top right of the store screen -> *Order
   History* shows the new order with its green **PAID** badge.

---

## 6. Tests

```powershell
flutter test
```

* `test/app_config_test.dart` - the configuration points at the right project
* `test/product_model_test.dart` - the product mapping
* `test/widget_test.dart` - the store, the checkout flow with the green
  snackbar, the order history and the green `PAID` badge
* `supabase/tests/01_rls_verification.sql` - proves that the client cannot
  create an order or mark it as paid

---

## 7. How the payment flow works

```
 Flutter app                Supabase                Xendit
     │                          │                      │
     │ 1. Buy Now              │                      │
     │─────────────────────────▶│                      │
     │                          │ create order (PENDING)│
     │ 2. invoice_url          │ POST /v2/invoices ───▶│
     │◀─────────────────────────│◀─────────────────────│
     │ 3. WebView checkout      │                      │
     │─────────────────────────────────────────────────▶│
     │                          │   "Invoices paid"     │
     │                          │◀─────────────────────│
     │                          │ verify token → PAID  │
     │ 4. tap "Done" → read DB  │                      │
     │─────────────────────────▶│                      │
     │ 5. "Payment Verified!"   │                      │
```

The client can **never** mark an order as paid - there is no `update` policy
on the `orders` table. Only the webhook (service role) may set `PAID`.
