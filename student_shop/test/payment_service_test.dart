import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:student_shop/models/product_model.dart';
import 'package:student_shop/services/payment_service.dart';
import 'package:student_shop/services/session_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records the call and answers with a prepared response.
class FakeInvoiceInvoker implements InvoiceInvoker {
  FakeInvoiceInvoker({this.status = 201, this.data});

  int status;
  Object? data;

  String? functionName;
  Map<String, String>? headers;
  Object? body;

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    this.functionName = functionName;
    this.headers = headers;
    this.body = body;
    return FunctionResponse(data: data, status: status);
  }
}

const Product keyboard = Product(
  id: '3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90',
  name: 'Mechanical Gaming Keyboard',
  description: 'RGB mechanical keyboard',
  price: 1500,
  imageUrl: '',
  stockQuantity: 25,
  isActive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('PaymentService.createInvoice', () {
    test('sends the product id and the quantity but never a price', () async {
      final FakeInvoiceInvoker invoker = FakeInvoiceInvoker(
        data: <String, dynamic>{
          'order_id': 'order-1',
          'invoice_id': 'inv-1',
          'invoice_url': 'https://checkout.xendit.co/web/inv-1',
          'amount': 150000,
          'amount_display': 1500,
          'currency': 'PHP',
          'quantity': 1,
        },
      );
      final PaymentService service = PaymentService(invoker: invoker);

      final CheckoutResult result = await service.createInvoice(
        product: keyboard,
        quantity: 1,
      );

      expect(invoker.functionName, 'create-invoice');
      final Map<String, dynamic> body = Map<String, dynamic>.from(
        invoker.body! as Map,
      );
      expect(body['product_id'], keyboard.id);
      expect(body['quantity'], 1);
      expect(body.containsKey('price'), isFalse);
      expect(body.containsKey('amount'), isFalse);
      expect(invoker.headers?['idempotency-key'], isNotEmpty);

      expect(result.orderId, 'order-1');
      expect(result.invoiceId, 'inv-1');
      expect(result.invoiceUrl, 'https://checkout.xendit.co/web/inv-1');
      expect(result.amount, 150000);
      expect(result.currency, 'PHP');
    });

    test('refuses to buy an out of stock product', () async {
      final PaymentService service = PaymentService(
        invoker: FakeInvoiceInvoker(),
      );
      const Product soldOut = Product(
        id: '1',
        name: 'Sold out',
        description: '',
        price: 100,
        imageUrl: '',
        stockQuantity: 0,
        isActive: true,
      );

      await expectLater(
        service.createInvoice(product: soldOut),
        throwsA(isA<PaymentException>()),
      );
    });

    test('refuses to buy a product that is not available', () async {
      final PaymentService service = PaymentService(
        invoker: FakeInvoiceInvoker(),
      );
      const Product unavailable = Product(
        id: '1',
        name: 'Unavailable',
        description: '',
        price: 100,
        imageUrl: '',
        stockQuantity: 10,
        isActive: false,
      );

      await expectLater(
        service.createInvoice(product: unavailable),
        throwsA(isA<PaymentException>()),
      );
    });

    test('refuses an invalid quantity before calling the server', () async {
      final FakeInvoiceInvoker invoker = FakeInvoiceInvoker();
      final PaymentService service = PaymentService(invoker: invoker);

      await expectLater(
        service.createInvoice(product: keyboard, quantity: 0),
        throwsA(isA<PaymentException>()),
      );
      await expectLater(
        service.createInvoice(product: keyboard, quantity: 99),
        throwsA(isA<PaymentException>()),
      );
      expect(invoker.functionName, isNull);
    });

    test('shows the error message of the edge function', () async {
      final FakeInvoiceInvoker invoker = FakeInvoiceInvoker(
        status: 409,
        data: <String, dynamic>{
          'error': true,
          'code': 'OUT_OF_STOCK',
          'message': 'Only 2 piece(s) left in stock.',
        },
      );
      final PaymentService service = PaymentService(invoker: invoker);

      await expectLater(
        service.createInvoice(product: keyboard),
        throwsA(
          isA<PaymentException>()
              .having(
                (PaymentException e) => e.message,
                'message',
                'Only 2 piece(s) left in stock.',
              )
              .having((PaymentException e) => e.code, 'code', 'OUT_OF_STOCK'),
        ),
      );
    });

    test('rejects a response without a checkout url', () async {
      final FakeInvoiceInvoker invoker = FakeInvoiceInvoker(
        status: 201,
        data: <String, dynamic>{'order_id': 'order-1', 'invoice_url': ''},
      );
      final PaymentService service = PaymentService(invoker: invoker);

      await expectLater(
        service.createInvoice(product: keyboard),
        throwsA(isA<PaymentException>()),
      );
    });

    test('stores the guest token that the server issued', () async {
      final FakeInvoiceInvoker invoker = FakeInvoiceInvoker(
        data: <String, dynamic>{
          'order_id': 'order-1',
          'invoice_id': 'inv-1',
          'invoice_url': 'https://checkout.xendit.co/web/inv-1',
          'amount': 150000,
          'currency': 'PHP',
          'guest_token': 'a' * 64,
        },
      );
      final SessionService session = SessionService();
      final PaymentService service = PaymentService(
        invoker: invoker,
        session: session,
      );

      await service.createInvoice(product: keyboard);

      expect(session.guestToken, 'a' * 64);
      expect(session.isGuestMode, isTrue);
    });
  });

  group('SessionService', () {
    test('creates a random guest token with 64 hex characters', () {
      final String token = SessionService.generateGuestToken();
      expect(token.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(token), isTrue);
      expect(SessionService.generateGuestToken(), isNot(token));
    });
  });
}
