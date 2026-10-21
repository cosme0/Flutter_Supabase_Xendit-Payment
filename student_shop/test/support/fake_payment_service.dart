import 'package:student_shop/models/product_model.dart';
import 'package:student_shop/services/payment_service.dart';

/// A [PaymentService] that never talks to the network.
class FakePaymentService extends PaymentService {
  FakePaymentService({
    this.products = const <Product>[],
    this.orders = const <Map<String, dynamic>>[],
    this.invoice = const <String, dynamic>{
      'invoice_url': 'https://checkout.xendit.co/demo',
      'external_id': 'demo-order-1',
    },
    this.status = 'PAID',
    this.error,
  });

  final List<Product> products;
  final List<Map<String, dynamic>> orders;
  final Map<String, dynamic> invoice;
  final String status;
  final Object? error;

  /// Every external id that was checked with [checkOrderStatus].
  final List<String> checkedExternalIds = <String>[];

  @override
  Future<List<Product>> fetchProducts() async {
    if (error != null) throw error!;
    return products;
  }

  @override
  Future<Map<String, dynamic>> createInvoice(Product product) async {
    if (error != null) throw error!;
    return invoice;
  }

  @override
  Future<String> checkOrderStatus(String externalId) async {
    checkedExternalIds.add(externalId);
    return status;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrders() async => orders;
}

/// The demo product of the catalogue.
Product demoProduct({int id = 1, String name = 'Mechanical Gaming Keyboard'}) {
  return Product(
    id: id,
    name: name,
    price: 1500,
    imageUrl: 'https://images.unsplash.com/photo-1595225476474-87563907a212',
  );
}
