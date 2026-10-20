import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/models/order_model.dart';

void main() {
  group('PaymentStatus', () {
    test('maps the raw database value', () {
      expect(PaymentStatus.fromRaw('PAID'), PaymentStatus.paid);
      expect(PaymentStatus.fromRaw('SETTLED'), PaymentStatus.paid);
      expect(PaymentStatus.fromRaw('PENDING'), PaymentStatus.pending);
      expect(PaymentStatus.fromRaw('EXPIRED'), PaymentStatus.expired);
      expect(PaymentStatus.fromRaw('FAILED'), PaymentStatus.failed);
      expect(PaymentStatus.fromRaw('CANCELLED'), PaymentStatus.cancelled);
      expect(PaymentStatus.fromRaw('something'), PaymentStatus.unknown);
      expect(PaymentStatus.fromRaw(null), PaymentStatus.unknown);
    });

    test('has a label for every state', () {
      expect(PaymentStatus.paid.label, 'PAID');
      expect(PaymentStatus.pending.label, 'PENDING');
      expect(PaymentStatus.expired.label, 'EXPIRED');
      expect(PaymentStatus.failed.label, 'FAILED');
      expect(PaymentStatus.cancelled.label, 'CANCELLED');
      expect(PaymentStatus.unknown.label, 'UNKNOWN');
    });
  });

  group('Order.fromMap', () {
    test('maps an order with its items', () {
      final Order order = Order.fromMap(<String, dynamic>{
        'id': 'order-1',
        'external_id': 'order-1',
        'status': 'PAID',
        'payment_status': 'PAID',
        'total_amount': 1500,
        'currency': 'PHP',
        'xendit_invoice_id': 'inv-1',
        'xendit_invoice_url': 'https://checkout.xendit.co/web/inv-1',
        'payment_method': 'GCASH',
        'created_at': '2026-01-01T10:00:00Z',
        'paid_at': '2026-01-01T10:05:00Z',
        'order_items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'item-1',
            'product_name': 'Mechanical Gaming Keyboard',
            'quantity': 1,
            'unit_price': 1500,
            'subtotal': 1500,
          },
        ],
      });

      expect(order.id, 'order-1');
      expect(order.isPaid, isTrue);
      expect(order.isPending, isFalse);
      expect(order.totalAmount, 1500.0);
      expect(order.currency, 'PHP');
      expect(order.xenditInvoiceId, 'inv-1');
      expect(order.paymentMethod, 'GCASH');
      expect(order.items, hasLength(1));
      expect(order.items.first.productName, 'Mechanical Gaming Keyboard');
      expect(order.items.first.quantity, 1);
      expect(order.itemTotal, 1500.0);
      expect(order.createdAt, isNotNull);
      expect(order.paidAt, isNotNull);
    });

    test('maps the json payload of the get_my_orders rpc', () {
      final Order order = Order.fromMap(<String, dynamic>{
        'id': 'order-2',
        'external_id': 'order-2',
        'status': 'PENDING',
        'payment_status': 'PENDING',
        'total_amount': 3000,
        'currency': 'PHP',
        'created_at': '2026-01-01T10:00:00Z',
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'item-1',
            'product_name': 'Mechanical Gaming Keyboard',
            'quantity': 2,
            'unit_price': 1500,
            'subtotal': 3000,
          },
        ],
      });

      expect(order.isPaid, isFalse);
      expect(order.isPending, isTrue);
      expect(order.items, hasLength(1));
      expect(order.items.first.quantity, 2);
    });

    test('an order without items does not break', () {
      final Order order = Order.fromMap(<String, dynamic>{
        'id': 'order-3',
        'payment_status': 'PENDING',
        'total_amount': 0,
      });

      expect(order.items, isEmpty);
      expect(order.itemTotal, 0);
      expect(order.isPaid, isFalse);
    });
  });
}
