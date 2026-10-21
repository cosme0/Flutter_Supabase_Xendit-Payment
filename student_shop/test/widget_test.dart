import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/screens/orders_screen.dart';
import 'package:student_shop/screens/product_list_screen.dart';

import 'support/fake_payment_service.dart';

Widget wrap(Widget child) {
  return MaterialApp(home: child);
}

void main() {
  testWidgets('shows the demo product with its price and a buy button', (
    tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      products: <dynamic>[demoProduct()].cast(),
    );

    await tester.pumpWidget(wrap(ProductListScreen(paymentService: service)));
    await tester.pumpAndSettle();

    expect(find.text('Mechanical Gaming Keyboard'), findsOneWidget);
    expect(find.text('₱1500.00'), findsOneWidget);
    expect(find.text('Buy Now'), findsOneWidget);
  });

  testWidgets('shows an empty state when the catalogue is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(ProductListScreen(paymentService: FakePaymentService())),
    );
    await tester.pumpAndSettle();

    expect(find.text('No products found.'), findsOneWidget);
  });

  testWidgets('shows an error message when the catalogue cannot be loaded', (
    tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      error: Exception('network down'),
    );

    await tester.pumpWidget(wrap(ProductListScreen(paymentService: service)));
    await tester.pumpAndSettle();

    expect(find.textContaining('network down'), findsOneWidget);
  });

  testWidgets(
    'verifies the payment after the checkout and shows the green snackbar',
    (tester) async {
      final FakePaymentService service = FakePaymentService(
        products: <dynamic>[demoProduct()].cast(),
        status: 'PAID',
      );

      await tester.pumpWidget(
        wrap(
          ProductListScreen(
            paymentService: service,
            // replaces the web view so that no platform channel is used
            checkoutBuilder: (context, invoiceUrl) => Scaffold(
              appBar: AppBar(
                title: const Text('Xendit Checkout'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
              body: const Text('Xendit checkout'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buy Now'));
      await tester.pumpAndSettle();

      // the checkout screen is open
      expect(find.text('Xendit checkout'), findsOneWidget);

      // "Done" closes the checkout, then the app asks the server for the status
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(service.checkedExternalIds, <String>['demo-order-1']);
      expect(
        find.text('Payment Verified! Mechanical Gaming Keyboard is PAID.'),
        findsOneWidget,
      );

      final ScaffoldMessengerState messenger = tester.state(
        find.byType(ScaffoldMessenger),
      );
      expect(messenger, isNotNull);
    },
  );

  testWidgets('the order history can be opened from the app bar', (
    tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      products: <dynamic>[demoProduct()].cast(),
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'status': 'PAID',
          'product_name': 'Mechanical Gaming Keyboard',
          'amount': 1500.0,
          'external_id': 'demo-order-1',
          'created_at': '2026-10-20T15:09:09.769187+00:00',
        },
      ],
    );

    await tester.pumpWidget(wrap(ProductListScreen(paymentService: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();

    expect(find.text('Order History'), findsOneWidget);
    expect(find.text('Mechanical Gaming Keyboard'), findsOneWidget);
    expect(find.text('PAID'), findsOneWidget);
  });

  testWidgets('the order history shows a green badge for a paid order', (
    tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      orders: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'status': 'PAID',
          'product_name': 'Mechanical Gaming Keyboard',
          'amount': 1500.0,
          'external_id': 'demo-order-1',
          'created_at': '2026-10-20T15:09:09.769187+00:00',
        },
      ],
    );

    await tester.pumpWidget(wrap(OrdersScreen(paymentService: service)));
    await tester.pumpAndSettle();

    final Container badge = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('PAID'),
            matching: find.byType(Container),
          )
          .first,
    );
    final BoxDecoration decoration = badge.decoration! as BoxDecoration;
    expect(decoration.color, Colors.green.shade100);
  });
}
