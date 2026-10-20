import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/product_model.dart';
import '../services/payment_service.dart';
import '../widgets/product_card.dart';
import '../widgets/state_views.dart';
import 'orders_screen.dart';
import 'xendit_webview_screen.dart';

/// The store: shows the catalogue and starts the Xendit checkout.
class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, this.paymentService});

  /// Allows the tests to inject a fake service.
  final PaymentService? paymentService;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late final PaymentService _paymentService;

  List<Product> _products = <Product>[];
  bool _isLoading = true;
  String? _errorMessage;
  String? _busyProductId;
  final Map<String, int> _quantities = <String, int>{};

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<Product> products = await _paymentService.fetchProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _describe(error);
      });
    }
  }

  int _quantityOf(Product product) => _quantities[product.id] ?? 1;

  void _setQuantity(Product product, int quantity) {
    final int limit = product.stockQuantity > 0
        ? product.stockQuantity.clamp(1, PaymentService.maxQuantity)
        : 1;
    setState(() {
      _quantities[product.id] = quantity.clamp(1, limit);
    });
  }

  Future<void> _handleBuy(Product product) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    setState(() => _busyProductId = product.id);

    CheckoutResult result;
    try {
      result = await _paymentService.createInvoice(
        product: product,
        quantity: _quantityOf(product),
      );
    } on PaymentException catch (error) {
      if (!mounted) return;
      setState(() => _busyProductId = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyProductId = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not start the checkout: ${_describe(error)}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final bool? finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => XenditWebViewScreen(
          invoiceUrl: result.invoiceUrl,
          orderId: result.orderId,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    if (finished == true) {
      await _verifyPayment(result, product, messenger);
    }

    if (mounted) {
      setState(() => _busyProductId = null);
    }
  }

  /// Asks the server whether the payment really arrived.
  Future<void> _verifyPayment(
    CheckoutResult result,
    Product product,
    ScaffoldMessengerState messenger,
  ) async {
    final bool isPaid = await _paymentService
        .waitForPaidStatus(result.orderId)
        .then((order) => order != null && order.isPaid);

    if (!mounted) return;

    if (isPaid) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Payment Verified! ${product.name} is PAID.'),
          backgroundColor: const Color(0xFF146C2E),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'The payment for ${product.name} is still pending. The order is '
            'updated as soon as Xendit confirms the payment.',
          ),
          backgroundColor: const Color(0xFF8A5A00),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Check again',
            onPressed: () => _verifyPayment(result, product, messenger),
          ),
        ),
      );
    }

    await _loadProducts();
  }

  String _describe(Object error) {
    if (error is PaymentException) return error.message;
    final String text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(AppConfig.appName),
            Text(
              'Flutter + Supabase + Xendit',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh catalogue',
            onPressed: _isLoading ? null : _loadProducts,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Order history',
            onPressed: _openOrderHistory,
            icon: const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _openOrderHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            OrdersScreen(paymentService: widget.paymentService),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading the catalogue...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return ErrorState(
        title: 'The catalogue could not be loaded',
        message: _errorMessage!,
        onRetry: _loadProducts,
      );
    }

    if (_products.isEmpty) {
      return EmptyState(
        icon: Icons.storefront_rounded,
        title: 'The store is empty',
        message:
            'No products are available yet. Add the demo products in the '
            'Supabase SQL editor and pull down to refresh.',
        action: FilledButton.icon(
          onPressed: _loadProducts,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _products.length,
        itemBuilder: (BuildContext context, int index) {
          final Product product = _products[index];
          return ProductCard(
            key: ValueKey<String>(product.id),
            product: product,
            quantity: _quantityOf(product),
            isBusy: _busyProductId == product.id,
            onQuantityChanged: (int value) => _setQuantity(product, value),
            onBuy: () => _handleBuy(product),
          );
        },
      ),
    );
  }
}
