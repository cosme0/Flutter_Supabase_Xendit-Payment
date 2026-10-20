import '../utils/formatters.dart';

/// A product of the student shop catalogue.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.stockQuantity,
    required this.isActive,
  });

  /// Primary key (uuid) of the product.
  final String id;

  /// Display name, e.g. `Mechanical Gaming Keyboard`.
  final String name;

  /// Long description shown on the product card.
  final String description;

  /// Price in pesos (major unit).
  final double price;

  /// Absolute url of the product image.
  final String imageUrl;

  /// Number of pieces that can still be bought.
  final int stockQuantity;

  /// `false` when the product was taken out of the catalogue.
  final bool isActive;

  /// True when the product can be bought right now.
  bool get canBePurchased => isActive && stockQuantity > 0;

  /// True when the product is active but sold out.
  bool get isSoldOut => isActive && stockQuantity <= 0;

  /// True when the product must not be shown as purchasable.
  bool get isUnavailable => !isActive;

  /// The price formatted as `₱1,500.00`.
  String get formattedPrice => formatPeso(price);

  /// Converts a row of the `products` table into a [Product].
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed product',
      description: map['description']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      imageUrl: map['image_url']?.toString() ?? '',
      stockQuantity: (map['stock_quantity'] as num?)?.toInt() ?? 0,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  @override
  String toString() => 'Product($id, $name, $price)';
}
