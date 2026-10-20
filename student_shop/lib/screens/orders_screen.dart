import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../services/payment_service.dart';
import '../utils/formatters.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badge.dart';

/// Shows the orders of the current customer including their payment status.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.paymentService});

  /// Allows the tests to inject a fake service.
  final PaymentService? paymentService;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final PaymentService _paymentService;

  /// Refreshes the orders when the customer comes back to the app (for
  /// example after the payment was confirmed in the browser).
  late final AppLifecycleListener _lifecycleListener;

  List<Order> _orders = <Order>[];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
    _lifecycleListener = AppLifecycleListener(onResume: _loadOrders);
    _loadOrders();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final List<Order> orders = await _paymentService.fetchOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
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

  String _describe(Object error) {
    if (error is PaymentException) return error.message;
    final String text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: _isLoading ? null : _loadOrders,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ErrorState(
        title: 'The orders could not be loaded',
        message: _errorMessage!,
        onRetry: _loadOrders,
      );
    }

    if (_orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No orders yet',
        message:
            'Orders appear here as soon as you buy something in the store.',
        action: FilledButton.icon(
          onPressed: _loadOrders,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _orders.length,
        itemBuilder: (BuildContext context, int index) =>
            _OrderCard(order: _orders[index]),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Order ${shortenReference(order.id)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                StatusBadge(status: order.paymentStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatOrderDate(order.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            for (final OrderItem item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${item.quantity} x ${item.productName}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      formatPeso(item.subtotal),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            if (order.items.isEmpty)
              Text(
                'No items recorded for this order.',
                style: theme.textTheme.bodySmall,
              ),
            const Divider(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Total',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  formatPeso(order.totalAmount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (order.paymentMethod != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                'Payment method: ${order.paymentMethod}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (order.paidAt != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                'Paid on ${formatOrderDate(order.paidAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (order.xenditInvoiceId != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                'Xendit invoice: ${order.xenditInvoiceId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
