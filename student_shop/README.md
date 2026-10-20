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
| Supabase project | `BMC-ecom1` (organization `BMC`), project ref `iiznhatxciycwghihnaq` |

---

## 0. What is still missing (checklist)

The code is complete and tested. To make the app work on a device these four
steps are still open:

- [ ] **1. Publishable key** - copy it from the Supabase Dashboard
      (Project Settings -> API Keys) into `student_shop/.env`
      (`SUPABASE_PUBLISHABLE_KEY=...`).
- [ ] **2. Deploy the backend** - in `student_shop`:

      ```powershell
      supabase login                                          # approve in the browser
      supabase link --project-ref iiznhatxciycwghihnaq
      supabase secrets set --env-file supabase/.env.local
      supabase functions deploy create-invoice
      supabase functions deploy xendit-webhook
      supabase db push
      ```

      (or `powershell -ExecutionPolicy Bypass -File deploy.ps1` - the script
      does all of it. Use `supabase.cmd` instead of `supabase` if PowerShell
      blocks the `.ps1` shim.)
- [ ] **3. Xendit webhook** - Dashboard -> Developers -> Webhooks -> add
      `https://iiznhatxciycwghihnaq.supabase.co/functions/v1/xendit-webhook`,
      event *Invoices paid*, token
      `wNX7EvX6OdeF23EHH7ehzwC6hkG9uyxEd9RSQaF35PTGDSVZ`.
- [ ] **4. Build + install the APK**

      ```bash
      flutter build apk --release --dart-define-from-file=.env
      flutter install --release
      ```

After step 2 the endpoints answer like this:

```
POST .../functions/v1/create-invoice    -> 400 {"code":"INVALID_PRODUCT_ID",...}  (my version)
POST .../functions/v1/xendit-webhook    -> 401 {"code":"INVALID_CALLBACK_TOKEN"}  (my version)
```

---

## 1. Features

**Store (`lib/screens/product_list_screen.dart`)**

* catalogue with product image, name, price, description and stock
* the demonstration product *Mechanical Gaming Keyboard* at **₱1,500.00**
* quantity selector (limited by the available stock)
* loading indicator, empty state and a readable error state with "Try again"
* products that are unavailable or out of stock cannot be bought
* pull to refresh

**Payment (`lib/services/payment_service.dart`)**

* calls the `create-invoice` edge function with a **product id and a
  quantity** - the price is never sent by the client
* the edge function reads the price and the stock from the database, creates a
  pending order and calls the Xendit API with the server side secret
* the returned invoice url is opened in the embedded Xendit checkout
  (`lib/screens/xendit_webview_screen.dart`)
* the app **never** treats a closed checkout page as a successful payment -
  it asks the server for the order status

**Order history (`lib/screens/orders_screen.dart`)**

* every order with its items, quantities, prices, date and payment status
* a green **PAID** badge - but only for orders that the server confirmed
* pending orders show a "Check again" action, the screen can be refreshed
* a customer only ever sees their own orders (Row Level Security)

---

## 2. Project structure

```
student_shop/
  lib/
    main.dart                              # entry point, theme, app shell
    config/app_config.dart                 # Supabase url / publishable key
    models/product_model.dart
    models/order_model.dart
    services/app_bootstrap.dart            # Supabase init + session
    services/payment_service.dart          # catalogue, invoice, order status
    services/session_service.dart          # Supabase user or guest token
    screens/product_list_screen.dart       # the store
    screens/orders_screen.dart             # order history
    screens/xendit_webview_screen.dart     # Xendit checkout (webview)
    widgets/product_card.dart
    widgets/state_views.dart               # empty / error states
    widgets/status_badge.dart              # PAID / PENDING badge
    utils/formatters.dart                  # peso and date formatting
  test/                                    # 27 unit and widget tests
  supabase/                                # backend (see supabase/README.md)
    config.toml
    migrations/001_initial_schema.sql
    migrations/002_seed_demo_products.sql
    functions/_shared/                     # shared logic + 43 Deno tests
    functions/create-invoice/index.ts
    functions/xendit-webhook/index.ts
  android/                                 # Android project (INTERNET permission)
  .env.example                             # template for the local .env
```

---

## 3. Prerequisites

| Tool | Version used | Install |
| --- | --- | --- |
| Flutter | 3.47.3 (stable) | https://docs.flutter.dev/get-started/install |
| Dart | 3.13.3 | comes with Flutter |
| Android SDK | compileSdk 36, minSdk 24 | Android Studio / sdkmanager |
| Supabase CLI | latest | `npm install -g supabase` (or `brew install supabase`) |
| Deno | 2.x (only for the backend tests) | https://docs.deno.com/runtime/getting_started/installation/ |
| Xendit account | test mode | https://dashboard.xendit.co |

Check your setup:

```bash
flutter doctor
flutter --version
supabase --version
```

---

## 4. Get the code

```bash
git clone https://github.com/RM-afk/student_shop.git
cd student_shop
flutter pub get
```

> There is **no** `flutter add` command. To add a package use
> `flutter pub add supabase_flutter webview_flutter` (the dependencies are
> already listed in `pubspec.yaml` of this project).

---

## 5. Configure the local environment

The application only needs the **public** Supabase values. Create a local
`.env` file (it is git ignored):

```bash
cp .env.example .env        # Windows PowerShell: Copy-Item .env.example .env
```

```dotenv
SUPABASE_URL=https://iiznhatxciycwghihnaq.supabase.co
SUPABASE_PUBLISHABLE_KEY=<publishable key of BMC-ecom1>
```

You find both values in the Supabase Dashboard -> **Project Settings -> API**.

> Never put the Supabase **service role** key, the **Xendit secret key** or
> the **Xendit webhook token** into `.env`, into the Flutter code or into git.
> They are stored as Supabase edge function secrets (see section 8).

Start the app with the values of `.env`:

```bash
flutter run --dart-define-from-file=.env
```

Without the file the app starts and shows a *Configuration required* screen
that explains what is missing. As a convenience the app also reads a `.env`
file from the working directory at start up, so `flutter run` without the flag
works on the desktop as well. The **APK always uses the values that were
compiled into it** - always build it with the flag:

```bash
flutter build apk --release --dart-define-from-file=.env
# or: powershell -ExecutionPolicy Bypass -File build-apk.ps1
```

---

## 6. Set up the database

Full instructions: [`supabase/README.md`](supabase/README.md). Short version:

1. Supabase Dashboard -> project **BMC-ecom1** -> **SQL Editor -> New query**.
2. Run `supabase/migrations/001_initial_schema.sql`.
3. Run `supabase/migrations/002_seed_demo_products.sql`.

The second script inserts the demo catalogue (Mechanical Gaming Keyboard
₱1,500.00, Wireless Gaming Mouse ₱450.00, USB-C Docking Hub ₱850.00) and can
be executed again at any time.

---

## 7. Xendit test mode

1. Create an account on <https://dashboard.xendit.co> and stay in **test
   mode** (the keys start with `xnd_development_`).
2. **Developers -> API Keys** -> copy the **secret** key (test mode).
3. Xendit Dashboard -> **Developers -> Webhooks / Callbacks** -> add the callback url of the
   deployed webhook function and choose the event *Invoices paid*:

   ```
   https://iiznhatxciycwghihnaq.supabase.co/functions/v1/xendit-webhook
   ```

4. Generate a random verification token (for example
   `openssl rand -hex 24`) and use the **same value** for the Xendit webhook
   settings and for the `XENDIT_WEBHOOK_TOKEN` secret.

The checkout page shows the payment methods that are activated for your test
account (GCash / Maya / QRIS / cards). In test mode no real money is moved -
follow the test instructions of the Xendit dashboard.

---

## 8. Deploy the edge functions and their secrets

> **Windows note:** use `supabase.cmd` (not `supabase`) if PowerShell refuses to
> run the `.ps1` shim ("running scripts is disabled on this system"), and start
> the helper script with
> `powershell -ExecutionPolicy Bypass -File deploy.ps1`.

The fastest way is the helper script - it links the project, uploads the
secrets, deploys both functions and applies the migrations:

```powershell
Copy-Item supabase\.env.local.example supabase\.env.local   # add the secrets
powershell -ExecutionPolicy Bypass -File deploy.ps1           # asks for the login
```

The equivalent manual steps:

```bash
supabase login
supabase link --project-ref iiznhatxciycwghihnaq

# secrets (never in git!)
supabase secrets set --env-file supabase/.env.local

# functions
supabase functions deploy create-invoice
supabase functions deploy xendit-webhook

# database
supabase db push
```

Dashboard alternative: **Edge Functions -> Secrets -> Add new secret**.

The `supabase/.env.local` file holds the two server side secrets
(`XENDIT_SECRET_KEY`, `XENDIT_WEBHOOK_TOKEN`) and is git ignored - only
`supabase/.env.local.example` (placeholders) is committed.

> The checkout page shows the channels that are activated for your Xendit
> account. On the demo account that is **GCash**; Maya and the other channels
> are not activated. If you want to restrict the list explicitly, set the
> secret `XENDIT_PAYMENT_METHODS=GCASH,MAYA` and redeploy.

Why `verify_jwt = false`?

* `xendit-webhook` **must** disable it - Xendit calls the endpoint server to
  server without a Supabase JWT. The function therefore validates the
  `x-callback-token` header against the `XENDIT_WEBHOOK_TOKEN` secret
  (constant time comparison). Without that check anybody could mark orders as
  paid.
* `create-invoice` disables it so that guest checkouts work. The function
  verifies a supplied JWT itself (server side, against Supabase Auth) and
  rejects invalid tokens with `401`. Set `verify_jwt = true` in
  `supabase/config.toml` if you only want signed in customers.

---

## 9. Build the Android APK

```bash
flutter pub get
flutter build apk --release --dart-define-from-file=.env
```

The APK is written to:

```
build/app/outputs/flutter-apk/app-release.apk
```

Install it on a device with

```bash
flutter install --release
```

or copy the APK to the phone and open it (enable *unknown sources*).

> The release build is signed with the debug key (the default of the Flutter
> template). For a Play Store release create your own keystore and configure
> it in `android/app/build.gradle.kts`.

Requirements of the device: Android 7.0 (API 24) or newer, internet access.

---

## 10. Tests and quality checks

```bash
flutter analyze                 # No issues found!
flutter test                    # 27 tests, all passed
dart format lib test            # formatting

# backend logic (Deno)
deno test --allow-env supabase/functions/_shared
# ok | 43 passed | 0 failed

# type check of the edge functions
deno check supabase/functions/create-invoice/index.ts
deno check supabase/functions/xendit-webhook/index.ts

# the database migration against a real PostgreSQL (optional)
npm install @electric-sql/pglite
node supabase/tests/pglite_migration_test.mjs
# 51/51 checks passed

# the migration on a project that still has the tables of the old
# reference implementation
node supabase/tests/pglite_legacy_upgrade_test.mjs
# 29/29 checks passed
```

The last command runs `supabase/migrations/001_initial_schema.sql` and
`002_seed_demo_products.sql` against a PostgreSQL that runs inside the
process (PGlite) and then verifies the tables, the RLS policies, the order
creation, the stock reservation, the webhook handling (paid / expired /
duplicate / mismatch) and the guest checkout.

What is covered:

| Area | Test |
| --- | --- |
| catalogue | loading, error state, empty state, sold out product |
| invoice | sends product id + quantity but never a price, rejects invalid quantity, shows the server error, stores the guest token |
| order status | only `PAID` when the server says so, polling until the webhook arrives |
| order history | green PAID badge, pending badge, error state, refresh |
| edge function | invalid input, unknown/unavailable product, out of stock, Xendit failure, idempotent retry, guest token issuing |
| webhook | token rejection (missing / wrong), malformed payload, paid / expired / failed / duplicate / unknown notifications, database failure -> 500 so that Xendit retries |

---

## 11. Demonstration script

1. Install the APK and open **Student Shop**.
2. The catalogue shows the *Mechanical Gaming Keyboard* at **₱1,500.00**.
3. Tap **Buy Now** -> the app calls the `create-invoice` edge function and
   opens the Xendit checkout page.
4. Choose a test payment method (GCash / Maya) and complete the simulated
   payment.
5. Xendit sends the webhook to Supabase; the edge function validates the
   token, the amount and the currency and sets the order to `PAID`.
6. Tap **Done** in the app bar. The app asks the server for the status and
   shows `Payment Verified! Mechanical Gaming Keyboard is PAID.`
7. Open the order history with the receipt icon in the app bar - the order
   is listed with a green **PAID** badge.

If the webhook is still on its way the app shows the pending status and offers
a **Check again** action - it never shows a false success message.

---

## 12. Troubleshooting

| Symptom | Cause / solution |
| --- | --- |
| "Configuration required" screen | `.env` is missing or `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` are wrong. Rebuild with `--dart-define-from-file=.env`. |
| `Failed to create invoice: 401` | The Supabase JWT was rejected. Sign out of the app, or enable anonymous sign-ins (Authentication -> Sign In / Providers -> Anonymous). |
| `XENDIT_NOT_CONFIGURED` | The `XENDIT_SECRET_KEY` secret is missing: `supabase secrets set XENDIT_SECRET_KEY=...` and redeploy the function. |
| `INVALID_CALLBACK_TOKEN` (401 in the Xendit dashboard) | The token in the Xendit webhook settings differs from the `XENDIT_WEBHOOK_TOKEN` secret. |
| The order stays `PENDING` | The webhook did not arrive. Check **Edge Functions -> Logs** of `xendit-webhook` and the **Webhooks** tab of the Xendit dashboard, then use *Resend*. |
| The checkout page stays white | The device has no internet, or the WebView was blocked. Try *Open in browser* inside the checkout screen. |
| `error: relation "public.orders" does not exist` | The SQL migration was not executed in the project **BMC-ecom1**. |
| The catalogue is empty | The seed script was not executed, or the product is inactive. |

---

## 13. Security notes

* The client never sends a price - the amount is calculated on the server.
* The client can never mark an order as `PAID`: there is no `update` policy on
  `orders` and only the webhook function (service role) writes to it.
* Customers only see their own orders (RLS `auth.uid() = user_id`).
* Guest orders are bound to a random token that is generated by the server;
  only its SHA-256 hash is stored in the database.
* The Xendit secret key and the webhook token live in Supabase edge function
  secrets and are never part of the APK.
* The webhook is authenticated with the `x-callback-token` header, the amount
  and the currency of the notification are checked against the order before it
  is marked as paid, and repeated deliveries are idempotent.

---

## 14. GitHub submission

The repository is named **`Flutter_Supabase_Xendit Payment`** and contains the
complete `student_shop` project.

```bash
cd student_shop
git init                     # only if the folder is not a repository yet
git add .
git commit -m "Act4 E-commerce Guidelines for BMC Finals Project Demonstration"
git branch -M main
git remote add origin https://github.com/<YOUR-USERNAME>/<REPOSITORY>.git
git push -u origin main
```

Commit message:

```
Act4 E-commerce Guidelines for BMC Finals Project Demonstration
```

`.env`, the build folder and the local Supabase state are git ignored, only
`.env.example` (with placeholders) is committed.
