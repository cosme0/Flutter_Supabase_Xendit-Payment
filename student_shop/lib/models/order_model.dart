/// The payment state of an order as reported by the server.
enum PaymentStatus {
  /// The invoice was created but the money did not arrive yet.
  pending,

  /// The server verified the payment (Xendit webhook).
  paid,

  /// The invoice expired before it was paid.
  expired,

  /// The payment failed.
  failed,

  /// The order was cancelled.
  cancelled,

  /// The server returned a status that the app does not know.
  unknown;

  /// Maps the raw database value to a [PaymentStatus].
  static PaymentStatus fromRaw(String? raw) {
    switch (raw?.trim().toUpperCase()) {
      case 'PAID':
      case 'SETTLED':
        return PaymentStatus.paid;
      case 'PENDING':
        return PaymentStatus.pending;
      case 'EXPIRED':
        return PaymentStatus.expired;
      case 'FAILED':
        return PaymentStatus.failed;
      case 'CANCELLED':
        return PaymentStatus.cancelled;
      default:
        return PaymentStatus.unknown;
    }
  }

  /// Label that is shown in the user interface.
  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'PENDING';
      case PaymentStatus.paid:
        return 'PAID';
      case PaymentStatus.expired:
        return 'EXPIRED';
      case PaymentStatus.failed:
        return 'FAILED';
      case PaymentStatus.cancelled:
        return 'CANCELLED';
      case PaymentStatus.unknown:
        return 'UNKNOWN';
    }
  }
}

/// A single line of an order.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final String id;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? 'Product',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// An order of the student shop.
class Order {
  const Order({
    required this.id,
    required this.externalId,
    required this.paymentStatus,
    required this.totalAmount,
    required this.currency,
    required this.items,
    this.xenditInvoiceId,
    this.xenditInvoiceUrl,
    this.paymentMethod,
    this.failureReason,
    this.createdAt,
    this.paidAt,
  });

  final String id;
  final String externalId;
  final PaymentStatus paymentStatus;
  final double totalAmount;
  final String currency;
  final List<OrderItem> items;
  final String? xenditInvoiceId;
  final String? xenditInvoiceUrl;
  final String? paymentMethod;
  final String? failureReason;
  final DateTime? createdAt;
  final DateTime? paidAt;

  /// True when the **server** confirmed that the order was paid.
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// True while the payment is still being processed.
  bool get isPending => paymentStatus == PaymentStatus.pending;

  /// The total amount of all items.
  double get itemTotal => items.fold<double>(
    0,
    (double sum, OrderItem item) => sum + item.subtotal,
  );

  /// Converts a database row (or the json payload of `get_my_orders`) into
  /// an [Order].
  factory Order.fromMap(Map<String, dynamic> map) {
    final Object? rawItems = map['items'] ?? map['order_items'];
    final List<OrderItem> items = <OrderItem>[];
    if (rawItems is List) {
      for (final Object? entry in rawItems) {
        if (entry is Map) {
          items.add(OrderItem.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    }

    return Order(
      id: map['id']?.toString() ?? '',
      externalId: map['external_id']?.toString() ?? '',
      paymentStatus: PaymentStatus.fromRaw(map['payment_status']?.toString()),
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      currency: map['currency']?.toString() ?? 'PHP',
      items: items,
      xenditInvoiceId: map['xendit_invoice_id']?.toString(),
      xenditInvoiceUrl: map['xendit_invoice_url']?.toString(),
      paymentMethod: map['payment_method']?.toString(),
      failureReason: map['failure_reason']?.toString(),
      createdAt: _parseDate(map['created_at']),
      paidAt: _parseDate(map['paid_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
