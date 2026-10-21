import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/payment_service.dart';
import 'orders_screen.dart';
import 'xendit_webview_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.paymentService, this.checkoutBuilder});

  /// Allows the tests to inject a fake service.
  final PaymentService? paymentService;

  /// Builds the screen that hosts the Xendit checkout.
  ///
  /// The tests replace it with a stub so that no web view is created.
  final Widget Function(BuildContext context, String invoiceUrl)?
  checkoutBuilder;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late final PaymentService _paymentService;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
  }

  Future<void> _handleBuyProduct(Product product) async {
    setState(() => _isProcessing = true);

    try {
      // 1. Ask Supabase Edge Function for a Xendit Checkout Link
      final invoiceData = await _paymentService.createInvoice(product);
      final String invoiceUrl = invoiceData['invoice_url'];
      final String externalId = invoiceData['external_id'];

      if (!mounted) return;

      // 2. Open the Checkout Link in our WebView screen and wait until user taps 'Done'
      final Widget checkout =
          widget.checkoutBuilder?.call(context, invoiceUrl) ??
          XenditWebViewScreen(invoiceUrl: invoiceUrl);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => checkout),
      );

      // 3. Check Supabase to see if the Xendit Webhook updated the order to PAID
      final String status = await _paymentService.checkOrderStatus(externalId);

      if (!mounted) return;
      if (status == 'PAID') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Verified! ${product.name} is PAID.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status is currently: $status'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Store'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Order History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      OrdersScreen(paymentService: _paymentService),
                ),
              );
            },
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting to Supabase & Xendit...'),
                ],
              ),
            )
          : FutureBuilder<List<Product>>(
              future: _paymentService.fetchProducts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final products = snapshot.data ?? [];
                if (products.isEmpty) {
                  return const Center(child: Text('No products found.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: product.imageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  product.imageUrl,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.shopping_bag, size: 40),
                                ),
                              )
                            : const Icon(Icons.shopping_bag, size: 40),
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('₱${product.price.toStringAsFixed(2)}'),
                        trailing: FilledButton(
                          onPressed: () => _handleBuyProduct(product),
                          child: const Text('Buy Now'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}