import 'package:flutter/material.dart';

import '../models/product_model.dart';

/// Card that shows a single product of the catalogue.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onBuy,
    this.isBusy = false,
    this.quantity = 1,
    this.onQuantityChanged,
  });

  final Product product;

  /// Called when the customer taps "Buy now".
  final VoidCallback onBuy;

  /// True while the checkout for this product is running.
  final bool isBusy;

  /// Currently selected quantity.
  final int quantity;

  /// Called when the customer changes the quantity.
  final ValueChanged<int>? onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canBuy = product.canBePurchased && !isBusy;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ProductImage(imageUrl: product.imageUrl, name: product.name),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.formattedPrice,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _StockLabel(product: product),
                    ],
                  ),
                ),
              ],
            ),
            if (product.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                product.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (onQuantityChanged != null) ...<Widget>[
                  Text('Quantity', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 12),
                  _QuantityStepper(
                    quantity: quantity,
                    enabled: canBuy,
                    maxQuantity: product.stockQuantity,
                    onChanged: onQuantityChanged ?? (int value) {},
                  ),
                ] else
                  const Spacer(),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canBuy ? onBuy : null,
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.shopping_bag_outlined),
                  label: Text(isBusy ? 'Loading...' : 'Buy Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl, required this.name});

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget placeholder = Container(
      width: 88,
      height: 88,
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.keyboard_alt_outlined,
        size: 36,
        color: theme.colorScheme.outline,
      ),
    );

    if (imageUrl.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            placeholder,
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return placeholder;
            },
      ),
    );
  }
}

class _StockLabel extends StatelessWidget {
  const _StockLabel({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool inStock = product.canBePurchased;
    final Color color = inStock
        ? const Color(0xFF146C2E)
        : theme.colorScheme.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          inStock ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          inStock
              ? 'In stock: ${product.stockQuantity}'
              : product.isUnavailable
              ? 'Unavailable'
              : 'Out of stock',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.enabled,
    required this.maxQuantity,
    required this.onChanged,
  });

  final int quantity;
  final bool enabled;
  final int maxQuantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int limit = maxQuantity > 0 ? maxQuantity : 1;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: enabled && quantity > 1
                ? () => onChanged(quantity - 1)
                : null,
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Decrease quantity',
          ),
          Text(
            '$quantity',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: enabled && quantity < limit
                ? () => onChanged(quantity + 1)
                : null,
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Increase quantity',
          ),
        ],
      ),
    );
  }
}
