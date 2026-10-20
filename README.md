# Flutter Supabase Xendit Payment

**Repository:** `Flutter_Supabase_Xendit Payment`
**Project folder:** [`student_shop/`](student_shop) — the Flutter application
**Commit message:** `Act4 E-commerce Guidelines for BMC Finals Project Demonstration`

A complete e‑commerce demonstration built with **Flutter**, **Supabase** and
**Xendit** (BMC Finals Project – Act 4). The customer buys a product from a
catalogue, pays with GCash/Maya through the Xendit hosted checkout, and the
order in the app is flipped to **PAID** only after the *server* confirmed the
payment through the Xendit webhook.

---

## 1. Submission links

| What | Link |
| --- | --- |
| 📦 Release APK (Google Drive) | *(filled in below)* |
| 🐙 Source code (GitHub) | https://github.com/cosme0/Flutter_Supabase_Xendit-Payment |

---

## 2. Tech stack

| Layer | Technology |
| --- | --- |
| App | Flutter 3.47 / Dart 3.13 (Android APK, Material 3) |
| Database | Supabase PostgreSQL (products, orders, order_items, guest_sessions, payment_webhook_events) |
| Backend | Supabase Edge Functions on Deno (`create-invoice`, `xendit-webhook`) |
| Payments | Xendit Invoice API `POST /v2/invoices` – **test mode** (GCash / Maya simulation) |
| Security | Row Level Security, service‑role key only on the server, verified status from the DB |

---

## 3. Repository layout

```
.
├── .gitignore
└── student_shop/                 ← the Flutter project (this is the "Git File")
    ├── android/                  Android host project (package com.example.student_shop)
    ├── lib/
    │   ├── config/app_config.dart        Supabase URL / publishable key (--dart-define)
    │   ├── models/                       product_model.dart, order_model.dart
    │   ├── screens/                      store, Xendit WebView, order history
    │   ├── services/                     payment_service.dart, session_service.dart, app_bootstrap.dart
    │   ├── widgets/                      product card, status badge, state views
    │   └── utils/formatters.dart         peso formatting
    ├── supabase/
    │   ├── migrations/                   001_initial_schema.sql, 002_seed_demo_products.sql
    │   ├── functions/                    create-invoice, xendit-webhook (+ unit tested _shared helpers)
    │   └── tests/                        RLS verification, negative tests, pglite migration tests
    ├── test/                            Flutter unit + widget tests
    ├── docs/FLUTTER_CODE.md             code walk‑through
    ├── build-apk.ps1                    one‑shot release build helper
    └── deploy.ps1                       one‑shot backend deployment helper
```

---

## 4. How the payment flow works

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
     │ 4. tap "Done" → poll DB  │                      │
     │─────────────────────────▶│                      │
     │ 5. "Payment Verified!"   │                      │
```

The client can **never** mark an order as paid – there is no `update` policy on
the `orders` table. Only `public.apply_xendit_invoice_event(...)` (service
role, called by the webhook) may set the status to `PAID`.

---

## 5. Setup

### 5.1 Supabase

1. Create a project on <https://supabase.com/dashboard>.
2. **Project Settings → API** → copy the *Project URL* and the *Publishable key*.
3. Run `student_shop/supabase/migrations/001_initial_schema.sql` and then
   `002_seed_demo_products.sql` in the SQL editor.
4. Add the edge function secrets (**Edge Functions → Secrets**):

   | Secret | Value |
   | --- | --- |
   | `XENDIT_SECRET_KEY` | `xnd_development_...` (Xendit **test mode** key) |
   | `XENDIT_WEBHOOK_TOKEN` | any random string, e.g. `openssl rand -hex 24` |

5. Deploy the functions:

   ```powershell
   cd student_shop
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase functions deploy create-invoice
   supabase functions deploy xendit-webhook
   ```

### 5.2 Xendit

Dashboard → **Developers → Webhooks** → add
`https://<your-project-ref>.supabase.co/functions/v1/xendit-webhook`,
event **Invoices paid**, and paste the same `XENDIT_WEBHOOK_TOKEN`.

### 5.3 Configure the app

```powershell
cd student_shop
copy .env.example .env     # Windows
```

```env
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

The `.env` file is **git‑ignored** – only the public publishable key is ever
compiled into the APK, never the service‑role key or the Xendit secret.

### 5.4 Build the release APK

```powershell
cd student_shop
flutter build apk --release --dart-define-from-file=.env
```

The APK is written to:

```
student_shop/build/app/outputs/flutter-apk/app-release.apk
```

> **Note:** on machines with *Windows Smart App Control / WDAC* enabled, Flutter's
> unsigned `font-subset.exe` helper is blocked by the Application Control policy.
> Add `--no-tree-shake-icons` to the command above (the icon font is then
> shipped un‑subsetted, which only makes the APK ~1 MB bigger).

---

## 6. Demonstration walk‑through

1. Install `app-release.apk` on an Android phone and open **Student Shop**.
2. Tap **Buy Now** on the *Mechanical Gaming Keyboard* (₱1,500.00).
3. The **Xendit WebView** opens → select **GCash** or **Maya** → tap the test
   simulation button.
4. Wait for Xendit's green receipt page inside the WebView – at that exact
   moment the Xendit webhook updates Supabase in the background.
5. Tap **Done** in the top‑right corner of the app bar.
6. A green snackbar appears: **“Payment Verified! Mechanical Gaming Keyboard is PAID.”**
7. Tap the **receipt icon** in the top‑right of the store screen → *Order
   History* shows the new order with its green **PAID** badge.

---

## 7. Tests

```powershell
cd student_shop
flutter test                 # Flutter unit + widget tests
```

The Supabase side ships Deno unit tests (`supabase/functions/_shared/*.test.ts`),
RLS verification and negative RLS tests, plus a pglite migration test.

---

## 8. Security notes

* The **service‑role key** and the **Xendit secret key** live only in Supabase
  Edge Function secrets – they are never part of the repository or the APK.
* The webhook rejects every callback whose token does not match
  `XENDIT_WEBHOOK_TOKEN`.
* `payment_webhook_events.event_key` is unique, so a replayed webhook cannot
  mark an order as paid twice.
