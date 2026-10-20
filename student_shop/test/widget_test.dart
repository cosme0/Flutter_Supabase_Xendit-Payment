import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/models/product_model.dart';
import 'package:student_shop/screens/product_list_screen.dart';

import 'support/fake_payment_service.dart';

void main() {
  testWidgets('shows the demo product with its price and a buy button', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      products: const <Product>[demoKeyboard],
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mechanical Gaming Keyboard'), findsOneWidget);
    expect(find.text('₱1,500.00'), findsOneWidget);
    expect(find.text('In stock: 25'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Buy Now'), findsOneWidget);
  });

  testWidgets('the buy button is disabled when the product is sold out', (
    WidgetTester tester,
  ) async {
    const Product soldOut = Product(
      id: '1',
      name: 'Sold out product',
      description: '',
      price: 100,
      imageUrl: '',
      stockQuantity: 0,
      isActive: true,
    );
    final FakePaymentService service = FakePaymentService(
      products: const <Product>[soldOut],
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Out of stock'), findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Buy Now'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('shows an error message when the catalogue cannot be loaded', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      error: Exception('network is down'),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The catalogue could not be loaded'), findsOneWidget);
    expect(find.text('network is down'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no products', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService();

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('The store is empty'), findsOneWidget);
    expect(
      find.textContaining('No products are available yet'),
      findsOneWidget,
    );
  });

  testWidgets('shows a loading indicator while the catalogue is fetched', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      products: const <Product>[demoKeyboard],
      delay: const Duration(milliseconds: 200),
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mechanical Gaming Keyboard'), findsOneWidget);
  });

  testWidgets('the order history can be opened from the app bar', (
    WidgetTester tester,
  ) async {
    final FakePaymentService service = FakePaymentService(
      products: const <Product>[demoKeyboard],
    );

    await tester.pumpWidget(
      MaterialApp(home: ProductListScreen(paymentService: service)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Order History'), findsOneWidget);
    expect(find.text('No orders yet'), findsOneWidget);
  });
}
