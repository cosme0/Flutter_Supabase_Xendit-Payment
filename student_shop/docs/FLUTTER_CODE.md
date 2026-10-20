# Flutter code - file by file

The required structure of the Act 4 guidelines is fully covered. The project
adds a few extra files (models, widgets, helpers) exactly as the guidelines
allow ("Create additional folders and files when needed, such as authentication
services, reusable widgets, and configuration helpers").

```
lib/
├── main.dart                          108 lines   app shell + theme + configuration screen
├── config/
│   └── app_config.dart                 40 lines   Supabase url / publishable key
├── models/
│   ├── product_model.dart              49 lines   catalogue product
│   └── order_model.dart               146 lines   order, order item, payment status
├── services/
│   ├── payment_service.dart           274 lines   catalogue + invoice + order status
│   ├── session_service.dart           100 lines   Supabase user or guest token
│   └── app_bootstrap.dart              46 lines   Supabase init before the first frame
├── screens/
│   ├── product_list_screen.dart       245 lines   the store
│   ├── orders_screen.dart             223 lines   order history
│   └── xendit_webview_screen.dart     251 lines   Xendit checkout (web view)
├── widgets/
│   ├── product_card.dart              227 lines   product card with quantity stepper
│   ├── status_badge.dart               62 lines   PAID / PENDING badge
│   └── state_views.dart               105 lines   empty state + error state
└── utils/
    └── formatters.dart                 50 lines   peso and date formatting
```

---

## 1. `lib/main.dart` - the entry point

Initialises the bindings and Supabase **before** the first frame, then shows
the store. If the Supabase configuration is missing the app explains what to
do instead of crashing.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBootstrap.initialize();
  runApp(const StudentShopApp());
}

class StudentShopApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: _buildTheme(),                 // Material 3, seed colour #1B4DB1
      home: AppBootstrap.isReady
          ? const ProductListScreen()
          : const ConfigurationRequiredScreen(),
    );
  }
}
```

`ConfigurationRequiredScreen` prints the exact commands:

```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=<publishable key>

flutter run --dart-define-from-file=.env
```

---

## 2. `lib/config/app_config.dart` - the configuration

Only **public** values. The service role key, the Xendit secret key and the
webhook token are never in the Flutter code.

```dart
class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseKey => supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;

  static bool get isSupabaseConfigured =>
      supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty;
}
```

The values are injected with `--dart-define-from-file=.env`.

---

## 3. `lib/models/product_model.dart` - the catalogue model

```dart
class Product {
  final String id;          // uuid
  final String name;
  final String description;
  final double price;       // pesos (major unit)
  final String imageUrl;
  final int stockQuantity;
  final bool isActive;

  bool get canBePurchased => isActive && stockQuantity > 0;
  bool get isSoldOut => isActive && stockQuantity <= 0;
  String get formattedPrice => formatPeso(price);

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Unnamed product',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        stockQuantity: (map['stock_quantity'] as num?)?.toInt() ?? 0,
        isActive: map['is_active'] as bool? ?? true,
        // ...
      );
}
```

---

## 4. `lib/models/order_model.dart` - orders and payment status

`PaymentStatus` is the single source of truth for the badge. Only
`PaymentStatus.paid` is rendered in green - it is set exclusively by the
server (webhook), never by the client.

```dart
enum PaymentStatus { pending, paid, expired, failed, cancelled, unknown }

class Order {
  final String id;
  final PaymentStatus paymentStatus;
  final double totalAmount;
  final String currency;
  final List<OrderItem> items;
  final String? xenditInvoiceId;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get isPaid => paymentStatus == PaymentStatus.paid;

  factory Order.fromMap(Map<String, dynamic> map) {
    // reads "items" (rpc payload) and "order_items" (embedded select)
  }
}
```

---

## 5. `lib/services/payment_service.dart` - the heart of the app

Four parts: the error type, the result of an invoice, an abstraction of the
edge function call (so the logic is unit testable) and the service itself.

### 5.1 The error type

```dart
class PaymentException implements Exception {
  PaymentException(this.message, {this.code});
  final String message;   // shown in the snack bar
  final String? code;     // machine readable code of the edge function
}
```

### 5.2 The result of `create-invoice`

```dart
class CheckoutResult {
  final String orderId;
  final String invoiceId;
  final String invoiceUrl;   // the Xendit checkout page
  final int amount;          // centavos
  final String currency;
  final String? guestToken;  // only for guest checkout
  final bool idempotentReplay;
}
```

### 5.3 The edge function abstraction (testability)

```dart
abstract class InvoiceInvoker {
  Future<FunctionResponse> invoke(String functionName,
      {Map<String, String>? headers, Object? body});
}

class SupabaseInvoiceInvoker implements InvoiceInvoker { ... }
```

`test/payment_service_test.dart` replaces it with a fake, so no server is
needed for the tests.

### 5.4 The service

```dart
class PaymentService {
  /// 1. the catalogue
  Future<List<Product>> fetchProducts() async {
    return _client
        .from('products')
        .select('id, name, description, price, image_url, stock_quantity, is_active')
        .eq('is_active', true)
        .order('name');
  }

  /// 2. start the checkout - the client NEVER sends a price
  Future<CheckoutResult> createInvoice({
    required Product product,
    int quantity = 1,
  }) async {
    if (!product.canBePurchased) {
      throw PaymentException('${product.name} is out of stock.',
          code: 'OUT_OF_STOCK');
    }
    if (quantity < 1 || quantity > maxQuantity) {
      throw PaymentException('Please choose between 1 and $maxQuantity pieces.',
          code: 'INVALID_QUANTITY');
    }

    final String idempotencyKey = _newIdempotencyKey();
    final FunctionResponse response = await _invoker.invoke(
      AppConfig.createInvoiceFunction,
      headers: {'idempotency-key': idempotencyKey},
      body: {
        'product_id': product.id,     // <- id and quantity only
        'quantity': quantity,
        'idempotency_key': idempotencyKey,
      },
    );

    if (response.status != 200 && response.status != 201) {
      throw PaymentException(_extractErrorMessage(response),
          code: _extractErrorCode(response));
    }
    // ...
  }

  /// 3. the order history (RLS protects it, guests use the rpc)
  Future<List<Order>> fetchOrders() async { ... }

  /// 4. the server verified status of a single order
  Future<Order?> fetchOrder(String orderId) async { ... }

  /// 5. poll the server until the webhook confirmed the payment
  Future<Order?> waitForPaidStatus(String orderId,
      {Duration timeout = const Duration(seconds: 20),
       Duration interval = const Duration(seconds: 2)}) async {
    final DateTime deadline = DateTime.now().add(timeout);
    Order? latest;
    while (true) {
      try {
        final Order? order = await fetchOrder(orderId);
        if (order != null) {
          latest = order;
          if (order.isPaid) return order;      // <- the ONLY success condition
        }
      } catch (_) {
        // a temporary network problem must not break the verification
      }
      if (DateTime.now().isAfter(deadline)) return latest;
      await Future<void>.delayed(interval);
    }
  }
}
```

**The app never decides that a payment succeeded.** It only shows what the
database returns, and the database is only changed by the webhook function.

---

## 6. `lib/services/session_service.dart` - who is buying

Two customer types:

* **signed in** - the app signs in anonymously (`signInAnonymously()`), so the
  order belongs to a real `auth.uid()` and the RLS policies apply
* **guest** - if anonymous sign-ins are disabled, the server issues a random
  token that is stored on the device (only its SHA-256 hash is in the database)

```dart
Future<void> ensureSession() async {
  if (isSignedIn) return;
  try {
    await _client.auth.signInAnonymously();
  } catch (error) {
    _guestToken = await _loadOrCreateGuestToken();   // guest fallback
  }
}

static String generateGuestToken() {
  final Random random = Random.secure();             // 32 bytes -> 64 hex chars
  // ...
}
```

---

## 7. `lib/services/app_bootstrap.dart` - the start up

```dart
static Future<void> initialize() async {
  if (!AppConfig.isSupabaseConfigured) {
    errorMessage = 'The Supabase configuration is missing ...';
    return;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );
  await session.ensureSession().timeout(const Duration(seconds: 20));
}
```

---

## 8. `lib/screens/product_list_screen.dart` - the store

Handles the three states (loading / error / empty) and the whole checkout
flow.

```dart
Future<void> _handleBuy(Product product) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  setState(() => _busyProductId = product.id);

  final CheckoutResult result = await _paymentService.createInvoice(
    product: product,
    quantity: _quantityOf(product),
  );

  // 1. open the Xendit checkout page
  final bool? finished = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => XenditWebViewScreen(
      invoiceUrl: result.invoiceUrl,
      orderId: result.orderId,
    )),
  );

  // 2. ask the SERVER whether the payment arrived
  if (finished == true) {
    await _verifyPayment(result, product, messenger);
  }
}

Future<void> _verifyPayment(CheckoutResult result, Product product,
    ScaffoldMessengerState messenger) async {
  final bool isPaid = await _paymentService
      .waitForPaidStatus(result.orderId)
      .then((order) => order != null && order.isPaid);

  if (isPaid) {
    messenger.showSnackBar(SnackBar(
      content: Text('Payment Verified! ${product.name} is PAID.'),
      backgroundColor: const Color(0xFF146C2E),
    ));
  } else {
    messenger.showSnackBar(SnackBar(
      content: Text('The payment for ${product.name} is still pending ...'),
      backgroundColor: const Color(0xFF8A5A00),
      action: SnackBarAction(
        label: 'Check again',
        onPressed: () => _verifyPayment(result, product, messenger),
      ),
    ));
  }
  await _loadProducts();   // refresh the stock
}
```

The app bar has the receipt icon that opens the order history.

---

## 9. `lib/screens/orders_screen.dart` - the order history

```dart
class _OrderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text('Order ${shortenReference(order.id)}')),
              StatusBadge(status: order.paymentStatus),   // <- green only for PAID
            ]),
            // items: quantity x name ... subtotal
            // total, payment method, paid on, xendit invoice id
          ],
        ),
      ),
    );
  }
}
```

The screen refreshes itself when the customer comes back to the app
(`AppLifecycleListener(onResume: _loadOrders)`) and supports pull to refresh.

---

## 10. `lib/screens/xendit_webview_screen.dart` - the checkout

```dart
final WebViewController controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(NavigationDelegate(
    onPageStarted: (_) => setState(() => _isLoading = true),
    onPageFinished: (_) => setState(() => _isLoading = false),
    onWebResourceError: (error) => setState(() {
      _errorMessage = 'The checkout page could not be loaded ...';
    }),
    onNavigationRequest: (request) =>
        request.url.startsWith('https://')   // only https inside the checkout
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
  ))
  ..loadRequest(Uri.parse(widget.invoiceUrl));
```

* **Done** button in the app bar -> `Navigator.pop(true)` -> back to the store
  -> the store asks the server for the status
* the back button asks *"Cancel checkout?"* before leaving
* loading overlay, error state with *Reload* and *Open in browser*

---

## 11. `lib/widgets/` - the reusable pieces

| Widget | Purpose |
| --- | --- |
| `ProductCard` | image, name, price, description, stock label, quantity stepper, *Buy Now* (disabled when sold out) |
| `StatusBadge` | the PAID / PENDING / EXPIRED badge (green only for a server verified payment) |
| `state_views.dart` | `EmptyState` and `ErrorState` (with a *Try again* button) |

---

## 12. `lib/utils/formatters.dart`

```dart
String formatPeso(num amount) => '${AppConfig.currencySymbol}$grouped.${cents}';
String formatOrderDate(DateTime? value);   // 20 Oct 2026, 3:04 PM
String shortenReference(String reference, {int maxLength = 8});
```

---

## Data flow of one purchase

```
ProductListScreen._handleBuy
        |
        |  product_id + quantity            (never a price)
        v
PaymentService.createInvoice  --->  Supabase edge function "create-invoice"
        |                                        |
        |                                   reads price + stock from the DB
        |                                   creates the pending order
        |                                   calls Xendit (secret key)
        v                                   stores invoice id + checkout url
CheckoutResult(invoiceUrl)
        |
        v
XenditWebViewScreen  --->  checkout.xendit.co  --->  customer pays (GCash)
        |  (Done)
        v
PaymentService.waitForPaidStatus  --->  SELECT orders   (server verified)
        |
        +--> PAID      -> "Payment Verified! ... is PAID."
        +--> PENDING   -> "still pending" + "Check again"

Xendit  --->  webhook  --->  edge function "xendit-webhook"
                              (x-callback-token + amount + currency)
                              --> public.apply_xendit_invoice_event(...)
                              --> order.payment_status = 'PAID'
```
