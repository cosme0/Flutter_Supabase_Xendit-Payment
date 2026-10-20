import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/models/product_model.dart';

void main() {
  group('Product.fromMap', () {
    test('maps a database row', () {
      final Product product = Product.fromMap(<String, dynamic>{
        'id': '3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90',
        'name': 'Mechanical Gaming Keyboard',
        'description': 'RGB mechanical keyboard',
        'price': 1500,
        'image_url': 'https://example.com/keyboard.jpg',
        'stock_quantity': 25,
        'is_active': true,
      });

      expect(product.id, '3f1a7c2e-5b4d-4a6f-9c1e-8d2b7a4f6e90');
      expect(product.name, 'Mechanical Gaming Keyboard');
      expect(product.price, 1500.0);
      expect(product.stockQuantity, 25);
      expect(product.isActive, isTrue);
      expect(product.canBePurchased, isTrue);
      expect(product.formattedPrice, '₱1,500.00');
    });

    test('falls back to safe defaults', () {
      final Product product = Product.fromMap(<String, dynamic>{});

      expect(product.id, '');
      expect(product.name, 'Unnamed product');
      expect(product.price, 0.0);
      expect(product.stockQuantity, 0);
      expect(product.isActive, isTrue);
      expect(product.canBePurchased, isFalse);
      expect(product.isSoldOut, isTrue);
    });

    test('a product that is not active cannot be purchased', () {
      final Product product = Product.fromMap(<String, dynamic>{
        'id': '1',
        'name': 'Old product',
        'price': 10,
        'stock_quantity': 5,
        'is_active': false,
      });

      expect(product.canBePurchased, isFalse);
      expect(product.isUnavailable, isTrue);
      expect(product.isSoldOut, isFalse);
    });

    test('a sold out product cannot be purchased', () {
      final Product product = Product.fromMap(<String, dynamic>{
        'id': '1',
        'name': 'Sold out product',
        'price': 10,
        'stock_quantity': 0,
        'is_active': true,
      });

      expect(product.canBePurchased, isFalse);
      expect(product.isSoldOut, isTrue);
    });
  });
}
