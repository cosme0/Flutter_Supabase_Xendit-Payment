import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/models/order_model.dart';
import 'package:student_shop/screens/orders_screen.dart';
import 'package:student_shop/widgets/status_badge.dart';

import 'support/fake_payment_service.dart';

Order _order({
  required String id,
  required PaymentStatus status,
  double total = 1500,
}) {
  return Order(
    id: id,
    externalId: id,
    paymentStatus: status,
    totalAmount: total,
    currency: 'PHP',
    createdAt: DateTime.utc(2026, 1, 1, 10),
    paidAt: status == PaymentStatus.paid
        ? DateTime.utc(2026, 1, 1, 10, 5)
        : null,
    paymentMethod: status == PaymentStatus.paid ? 'GCASH' : null,
    items: const <OrderItem>[
      OrderItem(
        id: 'item-1',
        productName: 'Mechanical Gaming Keyboard',
        quantity: 1,
        unitPrice: 1500,
        subtotal: 1500,
      ),
    ],
  );
}

void main() {
  testWidgets('shows a green PAID badge for a verified order', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      orders: <Order>[_order(id: 'order-1', status: PaymentStatus.paid)],
    );

    await tester.pumpWidget(
      MaterialApp(home: OrdersScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PAID'), findsOneWidget);
    expect(find.text('1 x Mechanical Gaming Keyboard'), findsOneWidget);
    expect(find.text('₱1,500.00'), findsNWidgets(2));
    expect(find.textContaining('Paid on'), findsOneWidget);

    final Finder badgeContainer = find.descendant(
      of: find.byType(StatusBadge),
      matching: find.byType(Container),
    );
    final Container container = tester.widget<Container>(badgeContainer.first);
    final BoxDecoration decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFD7F5DD));
  });

  testWidgets('shows a pending badge while the payment is not confirmed', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      orders: <Order>[_order(id: 'order-2', status: PaymentStatus.pending)],
    );

    await tester.pumpWidget(
      MaterialApp(home: OrdersScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('PAID'), findsNothing);
  });

  testWidgets('shows an error state when the orders cannot be loaded', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      error: Exception('permission denied'),
    );

    await tester.pumpWidget(
      MaterialApp(home: OrdersScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The orders could not be loaded'), findsOneWidget);
    expect(find.text('permission denied'), findsOneWidget);
  });

  testWidgets('the orders can be refreshed', (WidgetTester tester) async {
    final FakePaymentService service = FakePaymentService(
      orders: <Order>[_order(id: 'order-1', status: PaymentStatus.paid)],
    );

    await tester.pumpWidget(
      MaterialApp(home: OrdersScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();
    expect(service.fetchOrdersCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(service.fetchOrdersCalls, 2);
  });
}
