import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import 'session_service.dart';

/// Error that is shown to the user when a payment step fails.
class PaymentException implements Exception {
  PaymentException(this.message, {this.code});

  /// Message that can be shown in the user interface.
  final String message;

  /// Machine readable error code coming from the edge function.
  final String? code;

  @override
  String toString() => message;
}

/// The result of a successful `create-invoice` call.
class CheckoutResult {
  const CheckoutResult({
    required this.orderId,
    required this.invoiceId,
    required this.invoiceUrl,
    required this.amount,
    required this.currency,
    this.productName = '',
    this.quantity = 1,
    this.guestToken,
    this.idempotentReplay = false,
  });

  /// Id of the pending order inside Supabase.
  final String orderId;

  /// Id of the Xendit invoice.
  final String invoiceId;

  /// Url of the Xendit hosted checkout page.
  final String invoiceUrl;

  /// Amount in the minor unit of the currency (centavos).
  final int amount;

  /// Currency of the invoice.
  final String currency;

  /// Name of the product that was bought.
  final String productName;

  /// Number of pieces that were bought.
  final int quantity;

  /// Guest token that the server issued for this device.
  final String? guestToken;

  /// True when the server replayed an existing order instead of creating a
  /// new one (idempotent retry).
  final bool idempotentReplay;

  factory CheckoutResult.fromMap(Map<String, dynamic> map) {
    return CheckoutResult(
      orderId: map['order_id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      invoiceUrl: map['invoice_url']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      currency: map['currency']?.toString() ?? AppConfig.currencyCode,
      productName: map['product_name']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      guestToken: map['guest_token']?.toString(),
      idempotentReplay: map['idempotent_replay'] == true,
    );
  }
}

/// Abstraction over the Supabase edge function call so that the payment
/// logic can be unit tested without a real backend.
abstract class InvoiceInvoker {
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
  });
}

/// Default implementation that calls a Supabase edge function.
class SupabaseInvoiceInvoker implements InvoiceInvoker {
  SupabaseInvoiceInvoker([SupabaseClient? client]) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final SupabaseClient client = _injectedClient ?? Supabase.instance.client;
    return client.functions.invoke(functionName, headers: headers, body: body);
  }
}

/// Talks to Supabase: catalogue, orders and the Xendit checkout.
class PaymentService {
  PaymentService({
    SupabaseClient? client,
    InvoiceInvoker? invoker,
    SessionService? session,
  }) : _injectedClient = client,
       _invoker = invoker ?? SupabaseInvoiceInvoker(client),
       _session = session ?? SessionService(client: client);

  /// Maximum number of pieces a customer may buy in one order.
  static const int maxQuantity = 10;

  final SupabaseClient? _injectedClient;
  final InvoiceInvoker _invoker;
  final SessionService _session;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// The session service that knows the current customer.
  SessionService get session => _session;

  /// Loads the active catalogue.
  Future<List<Product>> fetchProducts() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('products')
        .select(
          'id, name, description, price, image_url, stock_quantity, is_active',
        )
        .eq('is_active', true)
        .order('name', ascending: true);

    return rows.map(Product.fromMap).toList();
  }

  /// Creates a Xendit invoice for the given product.
  ///
  /// The client never sends a price - the edge function reads the price and
  /// the stock from the database.
  Future<CheckoutResult> createInvoice({
    required Product product,
    int quantity = 1,
  }) async {
    if (!product.canBePurchased) {
      throw PaymentException(
        product.isUnavailable
            ? '${product.name} is not available for purchase.'
            : '${product.name} is out of stock.',
        code: product.isUnavailable ? 'PRODUCT_UNAVAILABLE' : 'OUT_OF_STOCK',
      );
    }
    if (quantity < 1 || quantity > maxQuantity) {
      throw PaymentException(
        'Please choose between 1 and $maxQuantity pieces.',
        code: 'INVALID_QUANTITY',
      );
    }

    final String idempotencyKey = _newIdempotencyKey();
    final Map<String, String> headers = <String, String>{
      'idempotency-key': idempotencyKey,
    };
    if (_session.isGuestMode && _session.guestToken != null) {
      headers['x-guest-token'] = _session.guestToken!;
    }

    final FunctionResponse response = await _invoker.invoke(
      AppConfig.createInvoiceFunction,
      headers: headers,
      body: <String, dynamic>{
        'product_id': product.id,
        'quantity': quantity,
        'idempotency_key': idempotencyKey,
      },
    );

    if (response.status != 200 && response.status != 201) {
      throw PaymentException(
        _extractErrorMessage(response),
        code: _extractErrorCode(response),
      );
    }

    final Object? data = response.data;
    if (data is! Map) {
      throw PaymentException(
        'The server returned an unexpected response.',
        code: 'INVALID_RESPONSE',
      );
    }

    final CheckoutResult result = CheckoutResult.fromMap(
      Map<String, dynamic>.from(data),
    );

    if (result.invoiceUrl.isEmpty) {
      throw PaymentException(
        'The payment provider did not return a checkout page.',
        code: 'INVALID_RESPONSE',
      );
    }

    final String? guestToken = result.guestToken;
    if (guestToken != null && guestToken.isNotEmpty) {
      await _session.saveGuestToken(guestToken);
    }

    return result;
  }

  /// Loads the orders of the current customer.
  Future<List<Order>> fetchOrders() async {
    if (_session.isGuestMode) {
      final Object? data = await _client.rpc(
        'get_my_orders',
        params: <String, dynamic>{'p_guest_token': _session.guestToken ?? ''},
      );
      return _mapOrders(data);
    }

    final List<Map<String, dynamic>> rows = await _client
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false);

    return rows.map(Order.fromMap).toList();
  }

  /// Loads a single order (used to verify the payment status).
  Future<Order?> fetchOrder(String orderId) async {
    if (_session.isGuestMode) {
      final List<Order> orders = await fetchOrders();
      for (final Order order in orders) {
        if (order.id == orderId) return order;
      }
      return null;
    }

    final Map<String, dynamic>? row = await _client
        .from('orders')
        .select('*, order_items(*)')
        .eq('id', orderId)
        .maybeSingle();

    if (row == null) return null;
    return Order.fromMap(row);
  }

  /// Polls the server until the order is paid or the timeout is reached.
  ///
  /// The result is always based on the database - the app never assumes that
  /// a payment succeeded because the checkout page was closed.
  Future<Order?> waitForPaidStatus(
    String orderId, {
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    Order? latest;

    while (true) {
      try {
        final Order? order = await fetchOrder(orderId);
        if (order != null) {
          latest = order;
          if (order.isPaid) return order;
        }
      } catch (_) {
        // A temporary network problem must not break the verification.
      }

      if (DateTime.now().isAfter(deadline)) {
        return latest;
      }
      await Future<void>.delayed(interval);
    }
  }

  List<Order> _mapOrders(Object? data) {
    if (data is! List) return <Order>[];
    final List<Order> orders = <Order>[];
    for (final Object? entry in data) {
      if (entry is Map) {
        orders.add(Order.fromMap(Map<String, dynamic>.from(entry)));
      }
    }
    return orders;
  }

  static String _newIdempotencyKey() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _extractErrorMessage(FunctionResponse response) {
    final Object? data = response.data;
    if (data is Map) {
      final Object? message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String && data.isNotEmpty) return data;
    return 'The payment could not be started (HTTP ${response.status}).';
  }

  static String? _extractErrorCode(FunctionResponse response) {
    final Object? data = response.data;
    if (data is Map) {
      final Object? code = data['code'];
      if (code is String && code.isNotEmpty) return code;
    }
    return null;
  }
}
