import 'package:flutter_test/flutter_test.dart';
import 'package:student_shop/models/product_model.dart';

void main() {
  group('Product.fromMap', () {
    test('reads every column of the products table', () {
      final Product product = Product.fromMap(<String, dynamic>{
        'id': 1,
        'name': 'Mechanical Gaming Keyboard',
        'price': 1500.0,
        'image_url': 'https://example.com/keyboard.png',
        'created_at': '2026-10-20T15:09:09.769187+00:00',
      });

      expect(product.id, 1);
      expect(product.name, 'Mechanical Gaming Keyboard');
      expect(product.price, 1500.0);
      expect(product.imageUrl, 'https://example.com/keyboard.png');
    });

    test('falls back to safe values for missing columns', () {
      final Product product = Product.fromMap(<String, dynamic>{});

      expect(product.id, 0);
      expect(product.name, 'Unnamed Item');
      expect(product.price, 0);
      expect(product.imageUrl, '');
    });
  });
}
