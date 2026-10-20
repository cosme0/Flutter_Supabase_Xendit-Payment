import 'package:student_shop/models/order_model.dart';
import 'package:student_shop/models/product_model.dart';
import 'package:student_shop/services/payment_service.dart';

/// A [PaymentService] that answers with prepared data instead of talking to
/// Supabase. Used by the widget tests.
class FakePaymentService extends PaymentService {
  FakePaymentService({
    this.products = const <Product>[],
    this.orders = const <Order>[],
    this.error,
    this.checkoutError,
    this.checkoutResult,
    this.orderAfterPayment,
    this.delay,
  });

  List<Product> products;
  List<Order> orders;
  Object? error;
  Object? checkoutError;
  CheckoutResult? checkoutResult;
  Order? orderAfterPayment;

  /// Artificial delay, used to test the loading states.
  Duration? delay;

  int fetchOrdersCalls = 0;
  int createInvoiceCalls = 0;

  @override
  Future<List<Product>> fetchProducts() async {
    final Duration? wait = delay;
    if (wait != null) {
      await Future<void>.delayed(wait);
    }
    final Object? failure = error;
    if (failure != null) throw failure;
    return products;
  }

  @override
  Future<List<Order>> fetchOrders() async {
    fetchOrdersCalls += 1;
    final Object? failure = error;
    if (failure != null) throw failure;
    return orders;
  }

  @override
  Future<CheckoutResult> createInvoice({
    required Product product,
    int quantity = 1,
  }) async {
    createInvoiceCalls += 1;
    final Object? failure = checkoutError;
    if (failure != null) throw failure;
    return checkoutResult ??
        const CheckoutResult(
          orderId: 'order-1',
          invoiceId: 'inv-1',
          invoiceUrl: 'https://checkout.xendit.co/web/inv-1',
          amount: 150000,
          currency: 'PHP',
        );
  }

  @override
  Future<Order?> waitForPaidStatus(
    String orderId, {
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(seconds: 2),
  }) async {
    return orderAfterPayment;
  }
}

/// The demo product of the Act 4 guidelines.
const Product demoKeyboard = Product(
  id: '3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90',
  name: 'Mechanical Gaming Keyboard',
  description:
      'A full-size 87-key mechanical gaming keyboard with RGB '
      'backlighting and tactile switches.',
  price: 1500,
  imageUrl: '',
  stockQuantity: 25,
  isActive: true,
);
